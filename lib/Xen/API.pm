=head1 NAME

Xen::API Perl interface to the Xen RPC-XML API.

=head1 SYNOPSIS

  use Xen::API;
  my $x = Xen::API->new;

  my %vms = $x->list_vms
  my %templates = $x->list_templates

  my $vm = $x->create_vm(template=>'my_template',cpu=>4,memory=>'16G',vmname=>'this_vm');

  my $vm_records = $x->Xen::API::VM::get_all_records();

=head1 DESCRIPTION

Perl interface to the Xen RPC-XML API. Contains some shortcuts for creating,
destroying, importing, and exporting VMs. All RPC API commands are available in
the Xen::API:: package space. Simply replace the dots with :: and prepend
Xen::API:: to the command, and execute it as if it were a perl function. Be
sure to pass the Xen object as the first parameter.

=head1 METHODS

=cut

package Xen::API;
#use AutoLoader 'AUTOLOAD';   # import the default AUTOLOAD subroutine
use strict;
use RPC::XML;
use RPC::XML::Client;
$RPC::XML::FORCE_STRING_ENCODING = 1;
use IO::Prompt;
#use Net::OpenSSH;
#use URI qw(scheme host);

use HTTP::Request;
#use Net::HTTP;
use Number::Format qw( unformat_number );
#use FileHandle;
#use Data::Dumper;
#use IO::Socket;
use Time::HiRes qw( tv_interval gettimeofday );

require Exporter;
our @ISA = qw(Exporter);

BEGIN {

  our @EXPORT_OK=qw(bool true false string Int i4 i8 double datetime
                 nil base64 array struct fault prompt mem xen run session_id get_console get_vm get_vm_ref);
  our %EXPORT_TAGS=(all=>\@EXPORT_OK);
  our $PACKAGE_PREFIX = __PACKAGE__;

  our $VERSION = '0.01';
}

=head2 prompt

Display a password prompt.

=cut

sub password {
  my $message = shift || 'Enter password: ';
  IO::Prompt::prompt($message, -e=>'*', '-tty').'';
}

sub input {
  my $message = shift || 'Enter a value: ';
  IO::Prompt::prompt($message, ).'';
}

=head2 mem

Convert suffix notation (k, M, G) to byte count. Useful for writing memory to give
to VM.

=cut

# sub mem { unformat_number(@_) }

=head2 bool true false string Int i4 i8 double datetime nil base64 array struct fault

shortcuts for RPC::XML explicit typecasts

=cut

sub bool { RPC::XML::boolean->new(@_) }
sub true { RPC::XML::boolean->new(1) }
sub false { RPC::XML::boolean->new(0) }
sub string { RPC::XML::string->new(@_) }
sub Int { RPC::XML::int->new(@_) }
sub i4 { RPC::XML::i4->new(@_) }
sub i8 { RPC::XML::i8->new(@_) }
sub double { RPC::XML::double->new(@_) }
sub datetime { RPC::XML::datetime_iso8601->new(@_) }
sub nil { RPC::XML::nil->new(@_) }
sub base64 { RPC::XML::base64->new(@_) }
sub array { RPC::XML::array->new(@_) }
sub struct { RPC::XML::struct->new(@_) }
sub fault { RPC::XML::fault->new(@_) }

=head2 xen

Create a new instance of a Xen class.

=cut

sub xen {Xen::API->new(@_)}

=head2 new($uri, $user, $password)

New Xen instance.

=cut

sub new {
	no strict;
  my $class = shift or return;
  my $uri = shift or die "Missing URI";
  my $user = shift || 'root';
  my $password = shift;

  my $self = {};
  bless $self, $class;
  require URI;
  $uri = "http://$uri" if !URI->new($uri)->scheme;
  $self->{host} = URI->new($uri)->host;
  $self->{uri} = $uri;
  #require RPC::XML::Client;
  #RPC::XML::Client->import('simple_request');
  #	$RPC::XML::FORCE_STRING_ENCODING = 1;
  $self->{xen} = RPC::XML::Client->new($self->{uri});
  # set up autoload packages for Xen API.
  my %seen;
  my %classes =
    map {(
      __PACKAGE__."::$_"=>__PACKAGE__,
      $PACKAGE_PREFIX? ("${PACKAGE_PREFIX}::$_"=>$PACKAGE_PREFIX) : ($_=>undef),
    )}
    map {s/\.[^.]*$//; s/\./::/g; !$seen{$_}++?$_:()}
    @{$self->{xen}->simple_request('system.listMethods')||[]};
  for my $c (keys %classes) {
    my $package = $classes{$c};
    my $eval = <<EOS;
      package $c;
      no warnings 'redefine';
      our \$AUTOLOAD;
      sub AUTOLOAD {
        my \$self = shift;
        \$AUTOLOAD=~s/^\\Q\${package}::\\E// if defined \$package;
        \$AUTOLOAD=~s/::/./g;
        \$self->request(\$AUTOLOAD,\@_);
      };
EOS
    eval $eval;
  }

  # login
  $self->{user} = $user;
  $password = prompt("Enter xen admin password for ".$self->{uri}.": ")
    if !defined($password);
  $self->{session} = $self->value(
    $self->{xen}->simple_request('session.login_with_password',$user,$password));
  return $self;
}

=head2 create_vm

Create a new VM.

Arguments:

    - vmname - The xen name of the VM.
    - template - The template to base the VM from.
    - cpu - How many CPUs to assign
    - memory - How much memory to assign
    - hostname - The hostname to set. Works for Debian/Ubuntu and RedHat/CentOS only.
    - sudo - Should sudo be used to edit the hostname config file?
    - user - SSH user name for editing the hostname config file
    - password - SSH password for editing the hostname config file
    - port - SSH port for editing the hostname config file

Returns a ref to the newly created VM.

=cut

#BEGIN {
#   my $lastpassword;
#   sub create_vm {
#     my $self = shift or return;
#
#     # read arguments
#     my %args = @_;
#     my $sudo=exists $args{sudo}?$args{sudo}:1;
#     my $user = $args{user};
#     $sudo=1 if !defined($sudo) && $user ne 'root';
#     my $password = exists $args{password}?$args{password}:$lastpassword;
#     my $vmname = defined $args{vmname}?$args{vmname}:$args{hostname};
#     my $hostname = $args{hostname};
#     my $port = $args{port};
#     my $cpu=$args{cpu};
#     my $memory=$args{memory};
#     my $template = $args{template} or return;
#     return if !defined $vmname || !defined $hostname;
#
#     # prompt for password
#     if (!defined($password)) {
#       $password = prompt("Enter login password: ");
#     }
#     $lastpassword = $password;
#
#     # get the list of VMs and templates in this pool
#     my %vms = %{$self->Xen::API::VM::get_all_records||{}};
#     my @templates = grep {$vms{$_}{is_a_template} && @{$vms{$_}{VBDs}||[]}} keys %vms;
#
#     # query for the template by name or uuid
#     my @use_template = grep {
#       $vms{$_}{name_label} eq $template
#         || $vms{$_}{uuid} eq $template
#         || $_ eq $template} @templates;
#     die "No template named \"$template\"!\n" if !@use_template;
#     die "Multiple templates found matching \"$template\":\n"
#       .join(', ',map {"\"$vms{$_}{name_label}\" ($vms{$_}{uuid})"} @use_template)
#       if @use_template>1;
#     my $use_template = $use_template[0];
#
#     # clone the template into a new VM
#     my $new_vm = $self->Xen::API::VM::clone($use_template,$vmname);
#
#     # set number of VCPUs
#     if (defined($cpu)) {
#       $self->Xen::API::VM::set_VCPUs_max($new_vm,$cpu);
#       $self->Xen::API::VM::set_VCPUs_at_startup($new_vm,$cpu);
#     }
#
#     # set memory
#     if (defined($memory)) {
#       my $mem = unformat_number($memory);
#       $self->Xen::API::VM::set_memory_limits($new_vm,$mem,$mem,$mem,$mem);
#       #$self->Xen::API::VM::set_memory_dynamic_min($new_vm,$mem);
#       #$self->Xen::API::VM::set_memory_dynamic_max($new_vm,$mem);
#       #$self->Xen::API::VM::set_memory_static_min($new_vm,$mem);
#       #$self->Xen::API::VM::set_memory_static_max($new_vm,$mem);
#     }
#
#     # provision the VM
#     $self->Xen::API::VM::provision($new_vm);
#
#     # start the VM
#     $self->Xen::API::VM::start($new_vm,false,true);
#
#     # set the hostname using SSH. This step is distro-specific, so try everything
#     # and see what sticks.
#     if (defined $hostname) {
#       # get the IP
#       my $ip = $self->get_ip($new_vm);
#
#       my $ssh = Net::OpenSSH->new($ip,
#         defined($user)?(user=>$user):(),
#         defined($password)?(password=>$password):(),
#         defined($port)?(port=>$port):(),
#         master_opts=>[-o=>'StrictHostKeyChecking=no'],
#       );
#       die "Couldn't establish SSH connection: ".$ssh->error if $ssh->error;
#       if ($sudo) {
#         $ssh->system({stdin_data=>"$password\n", quote_args=>1, stderr_discard=>1},
#           'sudo','-Sk','-p','--','sed','-ri','1,1s#^.*$#'.$hostname.'#','/etc/hostname');
#         $ssh->system({stdin_data=>"$password\n", quote_args=>1, stderr_discard=>1},
#           'sudo','-Sk','-p','--','sed','-ri','s#^HOSTNAME=.*#HOSTNAME='.$hostname.'#','/etc/sysconfig/network');
#       }
#       else {
#         $ssh->system({quote_args=>1, stderr_discard=>1},
#           'sed','-ri','1,1s#^.*$#'.$hostname.'#','/etc/hostname');
#         $ssh->system({quote_args=>1, stderr_discard=>1},
#           'sed','-ri','s#^HOSTNAME=.*#HOSTNAME='.$hostname.'#','/etc/sysconfig/network');
#       }
#       # reboot
#       $self->Xen::API::VM::clean_reboot($new_vm);
#     }
#     return $new_vm;
#   }
#}

=head2 get_ip

Gets the IP address of a VM.

=cut

sub get_ref {
  my $self = shift or return;
  my $type = shift or return;
  my $name = shift or return;
  if ( length($name) == 36 ) {
		return $self->request($type.'.get_by_uuid',$name);
	} else {
	  return if scalar @{$self->request($type.'.get_by_name_label',$name)} > 1; ## Don't return a ref if more than one matches
	  return @{$self->request($type.'.get_by_name_label',$name)}[0];
	}
}

sub get_record {
  my $self = shift or return;
  my $type = shift or return;
  my $ref = shift or return;
  return $self->request($type.'.get_record',$ref);
}

sub get_all_records {
  my $self = shift or return;
  my $type = shift or return;
  my $ref = shift or return;
  return $self->request($type.'.get_all_records',$ref);
}

sub get_all_records_where {
  my $self = shift or return;
  my $type = shift or return;
  my $ref = shift or return;
  my $opt = shift;
  return $self->request($type.'.get_all_records_where',$ref,$opt);
}

sub get_console_ref {
  my $self = shift or return;
  my $vm_name = shift or return;
  my $vm_ref = $self->get_ref('VM',$vm_name);
	return if !$vm_ref;
	my $vm_records = $self->get_record('VM',$vm_ref);
	foreach my $console_ref ( @{$vm_records->{'consoles'}} ) {
	  my $console_records = $self->get_record('console',$console_ref);
	  return $console_ref if ( $console_records->{'protocol'} eq 'rfb' );
	}
}


## Get RRD updates for a single VM
sub get_rrd_updates {
	my $self = shift || return;
	my $vm = shift || do {$self->error("VM required"); return;};
	my $start = shift || (time() - 300);  ## Default 5 minutes
	if ( !ref($vm) ) {
		my $vm_ref = $self->get_ref('VM',$vm) || return;
		$vm = $self->get_record('VM',$vm_ref) || return;
	}
	if ( !($vm->{power_state} =~ m/running/i) ) {
	  $self->error("VM not running\n");
	  return;
	}
	## We need to find the resident host
	my $host = $self->get_record('host',$vm->{resident_on}) || return;
	my $address = $host->{address} || return;
	
  require URI;
  require URI::QueryParam;
  my $uri = URI->new("http://$address");
  $uri->path('rrd_updates');
  $uri->query_param(session_id=>$self->{session});
  $uri->query_param(start=>$start);
  #$uri->query_param(uuid=>$vm_name);
  $uri->query_param(cf=>"AVERAGE");
  #$uri->query_param(host=>"FALSE");

	require LWP::UserAgent;
  my $ua = LWP::UserAgent->new;
  my $req = HTTP::Request->new(GET=>$uri->as_string);
  my $res = $ua->request($req);
  
  if ( !$res->is_success ) {
		$self->error($res->status_line);
 	  return;
	}
	return $res->decoded_content;
}


## Get whole RRD for a single VM
sub get_vm_rrd {
	my $self = shift || return;
	my $vm_uuid = shift || do {$self->error("VM required"); return;};

  require URI;
  require URI::QueryParam;
  my $uri = URI->new($self->{uri});
  $uri->path('vm_rrd');
  $uri->query_param(session_id=>$self->{session});
  $uri->query_param(uuid=>$vm_uuid);

	require LWP::UserAgent;
  my $ua = LWP::UserAgent->new;
  my $req = HTTP::Request->new(GET=>$uri->as_string);
  my $res = $ua->request($req);

  if ( !$res->is_success ) {
		$self->error($res->status_line);
 	  return;
	}
	return $res->decoded_content;
}
#
# sub get_metrics {
#
#
# }

sub set_locking {
	my $self = shift;
	my $vm_name = shift || return;
	my $params = shift;
	my $vm_ref = $self->get_ref('VM',$vm_name);
	die "Could not get VM ref for $vm_ref" if !$vm_ref;
	## Get VM records
	my $vm_records = $self->get_record('VM',$vm_ref);
	## Iterate through the VM's VIFs
	
	my $vmdata = {};
	if ( !$params ) {
	  $self->Xen::API::VM::set_xenstore_data($vm_ref,{'vm-data/networking' => ""});  ## Clear existing
	} else {
		foreach my $vif_ref ( @{$vm_records->{'VIFs'}} ) {
			## Get VIF records
			my $vif_records = $self->get_record('VIF',$vif_ref);
			## Get network records for VIF
			my $network_records = $self->get_record('network',$vif_records->{'network'});
			foreach my $network_label ( keys %{$params} ) {
				if ( $network_records->{'name_label'} =~ m/$network_label/i ) {
					## Label matches, generate policy
					my $mac = $vif_records->{'MAC'};
					$mac =~ s/://g;
					#print "Generating policy for ".$network_label." network, MAC ".$vif_records->{'MAC'}."\n";
					$vmdata->{'vm-data/networking/'.$mac.'/locking-mode'} = $params->{$network_label}->{'locking-mode'};
					$vmdata->{'vm-data/networking/'.$mac.'/ipv4-allowed'} = $params->{$network_label}->{'ipv4-allowed'};
					$vmdata->{'vm-data/networking/'.$mac.'/ipv6-allowed'} = $params->{$network_label}->{'ipv6-allowed'};
				}
			}
		}
	}
	if ( $vmdata ) {
	  #print "Applying policy\n";
	  $self->Xen::API::VM::set_xenstore_data($vm_ref,{'vm-data/networking' => ""});  ## Clear existing
		$self->Xen::API::VM::set_xenstore_data($vm_ref,$vmdata);  ## Add new
	} else {
	  #print "No policy to apply\n";
	  return 0;
	}
	## Return # of VIF policies applied
	return scalar (keys %{$vmdata});
}


# sub get_ip {
#   my $self = shift or return;
#   my $vmname = shift or return;
#   my $maxwait = shift;
#   $maxwait = 60 if !defined($maxwait);
#
#   my %vms = %{$self->Xen::API::VM::get_all_records||{}};
#   my @vms = grep {
#     $vms{$_}{name_label} eq $vmname
#       || $vms{$_}{uuid} eq $vmname
#       || $_ eq $vmname} keys %vms;
#   my $vm = $vms[0] or die "Could not find vm $vmname";
#   my $ip = $self->_get_ip($vm, $maxwait)
#     or die "Could not get IP address of VM $vmname: timeout";
#   return $ip;
# }

# sub _get_ip {
#   my $self = shift or return;
#   my $vm = shift or return;
#   my $maxwait = shift;
#   $maxwait=60 if !defined $maxwait;
#
#   # get the IP address of the VM
#   my $wait=0;
#   my $ip;
#   while (!$ip && $wait < $maxwait) {
#     eval {
#       my $vgm = $self->Xen::API::VM::get_guest_metrics($vm);
#       my $net = $self->Xen::API::VM_guest_metrics::get_networks($vgm);
#       $ip = $net->{'0/ip'} if $net;
#     };
#     $wait++;
#     sleep 1 if !$ip && $wait < $maxwait;
#   }
#   return $ip;
# }

=head2 destroy_vm

Destroys a VM and its associated VDIs.

=cut

# sub destroy_vm {
#   my $self = shift or return;
#   my $vmname = shift or return;
#
#   # find the VM
#   my %vms = %{$self->Xen::API::VM::get_all_records||{}};
#   my @vms = grep {
#     $vms{$_}{name_label} eq $vmname
#       || $vms{$_}{uuid} eq $vmname
#       || $_ eq $vmname} keys %vms;
#   die "Multiple VMs matched $vmname" if @vms > 1;
#   my $vm = $vms[0] or die "Could not find vm $vmname";
#
#   # make sure the VM is shut down
#   if (($vms{$vm}{power_state}||'') ne 'Halted') {
#     $self->Xen::API::VM::hard_shutdown($vm);
#   }
#
#   # destroy the attached VDIs
#   for my $vbd (@{$vms{$vm}{VBDs}||[]}) {
#     my $vbd_record = $self->Xen::API::VBD::get_record($vbd);
#     $self->Xen::API::VDI::destroy($vbd_record->{VDI})
#       if $vbd_record->{VDI} && $vbd_record->{VDI} ne 'OpaqueRef:NULL';
#   }
#
#   #destroy the VM
#   $self->Xen::API::VM::destroy($vm);
#   return '';
# }

=head2 import_vm

Import a VM from a xva file.

=cut

sub session {
	my $self = shift;
	return $self->{session};
}

# sub import_vm {
#   my $self = shift or return;
#   my $filename = shift or return;
#   my $sr_id = shift;
#
#   # find the storage repository if specified
#   my $sr_uuid;
#   if ($sr_id) {
#     my %sr = %{$self->Xen::API::SR::get_all_records||{}};
#     my @srs = grep {
#       $sr{$_}{name_label} eq $sr_id
#         || $sr{$_}{uuid} eq $sr_id
#         || $_ eq $sr_id} keys %sr;
#     my $sr = $srs[0]
#       or die "Could not find storage repository $sr_id";
#     $sr_uuid = $sr{$sr}{uuid};
#   }
#
#   # create the source and destination tasks
#   my $task = $self->Xen::API::task::create("import_$filename","Import VM $filename");
#
#   # URI
#   my $uri = URI->new($self->{uri});
#   $uri->path('import');
#   $uri->query_param(session_id=>$self->{session});
#   $uri->query_param(task_id=>$task);
#   $uri->query_param(sr_uuid=>$sr_uuid) if $sr_uuid;
#
#   my $net = Net::HTTP->new(Host=>$uri->host_port)
#     or die "Could not connect to host at ".$uri->host_port.": $@";
#   $net->write_request(
#     PUT=>$uri->path_query,
#     'Content-Length'=>(-s $filename));
#
#   my $fh = FileHandle->new($filename, 'r')
#     or die "Could not open $filename for reading: $!";
#   $fh->binmode;
#   my $chunk_size = 4096;
#   while ($fh->read(my $data, $chunk_size)) {
#     $net->print($data);
#   }
#   $fh->close;
#   # check HTTP status code
#   my ($code, $message, %headers) = $net->read_response_headers;
#   $net->close;
#   die "import returned HTTP Status code: $code" if $code != 200;
#
#   # Wait for the task status to be updated
#   my $wait=0;
#   my $maxwait=60;
#   my $task_record = $self->Xen::API::task::get_record($task);
#   while ($task_record && ($task_record->{status}||'') eq 'pending'
#            && $wait < $maxwait)
#   {
#     $task_record = $self->Xen::API::task::get_record($task);
#     sleep 1;
#     $wait++;
#   }
#   $self->Xen::API::task::destroy($task) if $task_record->{status} eq 'success' || $task_record->{status} eq 'failure';
#   die "Import task returned status $task_record->{status}: ".join(', ',@{$task_record->{error_info}||[]})
#       if $task_record->{status} ne 'success';
#   return '';
# }

=head2 export_vm

Export a VM to a xva file.

=cut

sub transfer_vm {
  my $self = shift or return;
  my $vmname = shift or return;
  my ($dest_host,$dest_user,$dest_pass,$sr_id) = @_;
  
  # find the source VM
  my $vm_ref = $self->get_ref('VM',$vmname) || die "Could not find VM '$vmname'";
  
  ## Create source task
	my $stask = $self->Xen::API::task::create("export_$vmname","Export VM $vmname");
	#require Time::HiRes;
	require IO::Socket::INET;
  # create source server socket
	my ($ssock,$dsock);

    if ( $ssock = IO::Socket::INET->new(PeerAddr => $self->{host}, PeerPort => 80, Proto => 'tcp', Blocking => 1, Timeout => 10)  )
    {
      if ( $ssock->connected )
      {
        print $ssock "GET /export/?session_id=$self->{session}&task_id=$stask&ref=$vm_ref HTTP/1.1\r\n";
        print $ssock "User-Agent: perl-Xen-API \r\n\r\n";
        $ssock->flush();

        # Parse Response Header
        my %headers;
        my $buf = "";
        my $n = 0;
        my @http_status;
				while  (my $tmp = <$ssock>)
				{
					last if $tmp  eq "\r\n";
					$tmp =~ s/\r\n//;
					@http_status = split(/ /,$tmp) if $n == 0;
					if ( ( my ($k,$v) = split(/: /, $tmp,2) ) && $n > 0 )
					{
					 $headers{lc($k)} = $v;
					}
					$n++;
				}
        #print("HTTP Status: $http_status[1]\n");
        goto KILLTASKS if $http_status[1] ne "200";
      } else {
        #print "ssock not connected\n";
        $ssock->close() if $ssock;
        goto KILLTASKS;
      }
    } else {
      #print "ssock connection timed out $! $self->{host}\n";
      goto KILLTASKS;
    }



	# Create destination server API handle
	my $d = Xen::API->new($dest_host,$dest_user,$dest_pass) || die $!;
	
  # find the destination storage repository if specified
  my $sr_uuid;
  if ($sr_id) {
		my $sr_ref = $d->get_ref('SR',$sr_id) || die "Could not find SR '$sr_id'";
    $sr_uuid = $d->get_record('SR',$sr_ref)->{'uuid'} || die "Could not find SR '$sr_id'";
  }

  # create the import task on destination server
  my $dtask = $d->Xen::API::task::create("import_$vmname","Import VM $vmname");
  
	# Creating destination socket
    if ( $dsock = IO::Socket::INET->new(PeerAddr => $d->{host}, PeerPort => 80, Proto => 'tcp', Blocking => 1, Timeout => 10)  )
    {
      if ( $dsock->connected )
      {
        print $dsock "PUT /import/?session_id=$d->{session}&task_id=$dtask".($sr_uuid?"&sr_uuid=$sr_uuid":"")." HTTP/1.1\r\n";
        print $dsock "User-Agent: perl-Xen-API \r\n\r\n";
        $dsock->flush();

        # Parse Response Header
        my %headers;
        my $buf = "";
        my $n = 0;
        my @http_status;
				while  (my $tmp = <$dsock>)
				{
					last if $tmp  eq "\r\n";
					$tmp =~ s/\r\n//;
					@http_status = split(/ /,$tmp) if $n == 0;
					if ( ( my ($k,$v) = split(/: /, $tmp,2) ) && $n > 0 )
					{
					 #notice("$k - $v");
					 $headers{lc($k)} = $v;
					}
					$n++;
				}
        #print("HTTP Status: $http_status[1]\n");
        goto KILLTASKS if $http_status[1] ne "200";
        my $x = 0;  ## For progress
        my $y = 0;  ## For progress
        my $z = 0;  ## For progress
        my $rate = 0;
        my $t0 = [gettimeofday()];
        $| = 1;
        while (<$ssock>)
        {
          ## Do some progress indication since this takes a while and things can go wrong
          if ($x > 10000) {
						if ( $y >= 20 ) {
							my $elapsed = tv_interval ( $t0, [gettimeofday()]);
							$rate = ($z/$elapsed)/1024;
							my $stask_record = $self->Xen::API::task::get_record($stask);
							print "\r                       ".sprintf("%.1f",$stask_record->{progress}*100)."%, ".sprintf("%.2f",$rate)." (KB/sec)\r";
							$y = 0;
							$z = 0;
							$t0 = [gettimeofday()];
						}
						print "."; $x = 0; $y++;
          	
					}
					print $dsock $_;
          $z = $z + length($_);
          $x++;
        }
        print "\r\nDone.\r\n";
        $dsock->flush();
        close($dsock);
#        return 1;
      } else {
        print "dsock not connected\n";
        $dsock->close() if $dsock;
        goto KILLTASKS;
      }
    } else {
      print "dsock connection timed out\n";
      goto KILLTASKS;
    }

		close($ssock);

	KILLTASKS:
	sleep 5;  ## Let tasks finish up
  my $dtask_record = $d->Xen::API::task::get_record($dtask);
  $d->Xen::API::task::destroy($dtask) if $dtask_record->{status} eq 'success' || $dtask_record->{status} eq 'failure';
  my $stask_record = $self->Xen::API::task::get_record($stask);
  $self->Xen::API::task::destroy($stask) if $stask_record->{status} eq 'success' || $stask_record->{status} eq 'failure';
  do {print "Export task returned status $dtask_record->{status}: ".join(', ',@{$dtask_record->{error_info}||[]}); return}
      if $dtask_record->{status} ne 'success';
  do {print "Import task returned status $stask_record->{status}: ".join(', ',@{$stask_record->{error_info}||[]}); return}
      if $stask_record->{status} ne 'success';
	#print Dumper  $dtask_record;
  return 1;

}

# sub export_vm {
#   my $self = shift or return;
#   my $vmname = shift or return;
#   my $filename = shift;
#
#   # find the VM
#   my %vms = %{$self->Xen::API::VM::get_all_records||{}};
#   my @vms = grep {
#     $vms{$_}{name_label} eq $vmname
#       || $vms{$_}{uuid} eq $vmname
#       || $_ eq $vmname} keys %vms;
#   my $vm = $vms[0] or die "Could not find vm $vmname";
#
#   my $task = $self->Xen::API::task::create("export_$vm","Export VM $vm");
#
#   # URI
#   my $uri = URI->new($self->{uri});
#   $uri->path('export');
#   $uri->query_param(session_id=>$self->{session});
#   $uri->query_param(task_id=>$task);
#   $uri->query_param(ref=>$vm);
#
#   my $ua = LWP::UserAgent->new;
#   my $req = HTTP::Request->new(GET=>$uri->as_string);
#   my $res = $ua->request($req, $filename);
#
#   my $task_record = $self->Xen::API::task::get_record($task);
#   $self->Xen::API::task::destroy($task) if $task_record->{status} eq 'success' || $task_record->{status} eq 'failure';
#   die "Export task returned status $task_record->{status}: ".join(', ',@{$task_record->{error_info}||[]})
#       if $task_record->{status} ne 'success';
#   return '';
# }


=head2 set_template

Set the is_a_template flag for a VM.

=cut

# sub set_template {
#   my $self = shift or return;
#   my $vmname = shift or return;
#   my $set_template = shift;
#   $set_template = 1 if !defined($set_template);
#
#   # find the VM
#   my %vms = %{$self->Xen::API::VM::get_all_records||{}};
#   my @vms = grep {
#     $vms{$_}{name_label} eq $vmname
#       || $vms{$_}{uuid} eq $vmname
#       || $_ eq $vmname} keys %vms;
#   my $vm = $vms[0] or die "Could not find vm $vmname";
#
#   $self->Xen::API::VM::set_is_a_template(
#     $vm,
#     $set_template?
#       ref($set_template)? $set_template : true
#     : false);
#   return '';
# }

=head2 list_vms

List the VMs on this Xen server.

=cut

# sub list_vms {
#   my $self = shift or return;
#   my %vms = %{$self->Xen::API::VM::get_all_records||{}};
#   my @vms = grep {!$vms{$_}{is_a_template}} keys %vms;
#   return map {{
#       name_label=>$vms{$_}{name_label},
#       uuid=>$vms{$_}{uuid},
#       ref=>$_,
#       power_state=>$vms{$_}{power_state},
#       ip=>($vms{$_}{power_state}||'') eq 'Running' ? $self->_get_ip($_,1) : undef,
#     }}
#     sort {$vms{$a}{name_label} cmp $vms{$b}{name_label}} @vms;
# }

=head2 list_templates

List the templates on this Xen server.

=cut
#
# sub list_templates {
#   my $self = shift or return;
#   my %vms = %{$self->Xen::API::VM::get_all_records||{}};
#   my @templates = grep {$vms{$_}{is_a_template} && @{$vms{$_}{VBDs}||[]}} keys %vms;
#   return map {{
#     name_label=>$vms{$_}{name_label},
#     uuid=>$vms{$_}{uuid},
#     ref=>$_,
#   }}
#     sort {$vms{$a}{name_label} cmp $vms{$b}{name_label}} @templates;
# }

=head2 list_hosts

List the physical hosts and related information.

=cut

# sub list_hosts {
#   my $self = shift or return;
#   my %hosts = %{$self->Xen::API::host::get_all_records||{}};
#   my %cpus = %{$self->Xen::API::host_cpu::get_all_records||{}};
#   my %metrics = map {$_=>$self->Xen::API::host_metrics::get_record($hosts{$_}{metrics})} keys %hosts;
#
#   return map {{
#     name_label=>$hosts{$_}{name_label},
#     uuid=>$hosts{$_}{uuid},
#     ref=>$_,
#     cpus=>scalar(@{$hosts{$_}{host_CPUs}||[]}),
#     %{$metrics{$_}},
#     memory_free=>format_bytes($metrics{$_}{memory_free}, mode=>'iec'),
#     memory_total=>format_bytes($metrics{$_}{memory_total}, mode=>'iec'),
#   }} sort {$hosts{$a}{name_label} cmp $hosts{$b}{name_labe}} keys %hosts;
# }

sub value {
  my $self = shift or return;
  my ($val) = @_;
  my ( $package, $filename, $line ) = caller(2);
  return $val && ($val->{Status}||'') eq "Success"
    ? ($val->{Value} || 1)
    : do {$self->error("[line ".$line."] Received status '$val->{Status}' from Xapi at ".$self->{uri}.": "
      .join(', ',@{$val->{ErrorDescription}||[]})); return undef};
}

sub request {
  my $self = shift or return;
  my $request = shift or return;
  #print $request."\n";
  #print Dumper(@_);
  return $self->value($self->{xen}->simple_request($request, $self->{session}, @_));
}

sub error {
  my $self = shift or return;
  my $msg = shift;
  if ( $msg ) {
  	$self->{error} = $msg;
  	return $msg;
   } else {
		my $tmp = $self->{error};
		undef $self->{error};
		return $tmp;
	}
}

1;

=head1 AUTHOR

Ben Booth, benwbooth@gmail.com

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2012 by Ben Booth

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.1 or,
at your option, any later version of Perl 5 you may have available.


=cut

