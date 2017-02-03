## Migrate XenServer VM's Between Servers

NOTE:  If you need a 32-bit binary of the script (and want to avoid compiling yourself), please see my blog post: http://djlab.com/2013/01/migrate-a-xenserver-vm-without-a-pool-or-shared-storage/

With the help of Ben Booth's Xen::API (Perl module I hacked up), I put together a VM migration script to export a VM directly to another host with no intermediary file. The transfer occurs over XAPI with no temp files or local disk interaction. This script can run directly on the source or destination host, or any server in between. Bear in mind, you will have the best speeds and least network overhead running this directly on the destination host.

Hint: You're best off compiling a static binary (check build.txt).  It would be nearly impossible to meet the dependencies on a live XenServer otherwise.

### Options:

	-sh  : source host
	-su  : source user (usually root)
	-sp  : source pass
	-sv  : source VM label or UUID
	-dh  : destination host
	-du  : destination user
	-dp  : destination pass
	-ds  : destination SR (optional)
	-ssl : flag to use SSL for the transfer of VM

If any of the options are omitted, you will be prompted for them.

###Example output:

	[root@cl-ash-h1 ~]# ./migratevm.pl
	Enter source host name/IP (blank = localhost): 1.2.3.4
	Enter username for 1.2.3.4 (blank = root):
	Enter password for 1.2.3.4: ************
	Enter source vm name or uuid on 1.2.3.4: my_vm
	Enter destination host name/IP (blank = localhost):
	Enter username for localhost (blank = root):
	Enter password for localhost: ******
	Destination SR on localhost (blank for default):
	Starting transfer
	...................    12.0%, 30618.43 (KB/sec)
	Done.

