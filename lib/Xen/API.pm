package Xen::API;
use strict;
use RPC::XML;
use RPC::XML::Client;
$RPC::XML::FORCE_STRING_ENCODING = 1;
use IO::Prompt;
use HTTP::Request;
use Number::Format qw( unformat_number );
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

sub password {
  my $message = shift || 'Enter password: ';
  IO::Prompt::prompt($message, -e=>'*', '-tty').'';
}

sub input {
  my $message = shift || 'Enter a value: ';
  IO::Prompt::prompt($message, ).'';
}

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
sub xen {Xen::API->new(@_)}

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

sub session {
	my $self = shift;
	return $self->{session};
}

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

