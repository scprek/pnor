#!/usr/bin/perl

use strict;
use File::Basename;

#my $ecc_tool_dir = "/opt/mcp/shared/fr_FLD8-1-20140528/opt/fsp/usr/bin"; #wh_todo

my $op_target_dir = "";
my $hb_image_dir = "";
my $scratch_dir = "";
my $hb_binary_dir = "";
my $targeting_binary_filename = "";
my $targeting_binary_source = "";
my $sbe_binary_filename = "";
my $sbec_binary_filename = "";
my $wink_binary_filename = "";
my $occ_binary_filename = "";
my $capp_binary_filename = "";
my $openpower_version_filename = "";
my $payload = "";
my $payload_filename = "";
my $xz_compression = 0;
my $secureboot = 0;
my $pnor_layout = "";
my $debug = 0;

while (@ARGV > 0){
    $_ = $ARGV[0];
    chomp($_);
    $_ = &trim_string($_);
    if (/^-h$/i || /^-help$/i || /^--help$/i){
        usage(); #print help content
        exit 0;
    }
    elsif (/^-op_target_dir/i){
        $op_target_dir = $ARGV[1] or die "Bad command line arg given: expecting a config type.\n";
        shift;
    }
    elsif (/^-hb_image_dir/i){
        $hb_image_dir = $ARGV[1] or die "Bad command line arg given: expecting a config type.\n";
        shift;
    }
    elsif (/^-scratch_dir/i){
        $scratch_dir = $ARGV[1] or die "Bad command line arg given: expecting a config type.\n";
        shift;
    }
    elsif (/^-hb_binary_dir/i){
        $hb_binary_dir = $ARGV[1] or die "Bad command line arg given: expecting a config type.\n";
        shift;
    }
    elsif (/^-targeting_binary_filename/i){
        $targeting_binary_filename = $ARGV[1] or die "Bad command line arg given: expecting a config type.\n";
        shift;
    }
    elsif (/^-targeting_binary_source/i){
        $targeting_binary_source = $ARGV[1] or die "Bad command line arg given: expecting a config type.\n";
        shift;
    }
    elsif (/^-sbe_binary_filename/i){
        $sbe_binary_filename = $ARGV[1] or die "Bad command line arg given: expecting a config type.\n";
        shift;
    }
    elsif (/^-sbec_binary_filename/i){
        $sbec_binary_filename = $ARGV[1] or die "Bad command line arg given: expecting a config type.\n";
        shift;
    }
    elsif (/^-wink_binary_filename/i){
        $wink_binary_filename = $ARGV[1] or die "Bad command line arg given: expecting a config type.\n";
        shift;
    }
    elsif (/^-occ_binary_filename/i){
        $occ_binary_filename = $ARGV[1] or die "Bad command line arg given: expecting a config type.\n";
        shift;
    }
    elsif (/^-capp_binary_filename/i){
        $capp_binary_filename = $ARGV[1] or die "Bad command line arg given: execting a config type.\n";
        shift;
    }
    elsif (/^-openpower_version_filename/i){
        $openpower_version_filename = $ARGV[1] or die "Bad command line arg given: expecting a config type.\n";
        shift;
    }
    elsif (/^-payload$/i){
        $payload = $ARGV[1] or die "Bad command line arg given: expecting a filepath to payload binary file.\n";
        shift;
    }
    elsif (/^-payload_filename/i){
        $payload_filename = $ARGV[1] or die "Bad command line arg given: expecting a filepath to payload binary file.\n";
        shift;
    }
    elsif (/^-xz_compression/i){
        $xz_compression = 1;
    }
    elsif (/^-secureboot/i){
        $secureboot = 1;
    }
    elsif (/^-pnor_layout/i){
        $pnor_layout = $ARGV[1] or die "Bad command line arg given: expecting a filepath to PNOR layout file.\n";
        shift;
    }
    else {
        print "Unrecognized command line arg: $_ \n";
        #print "To view all the options and help text run \'$program_name -h\' \n";
        exit 1;
    }
    shift;
}

# Compress the skiboot lid image with lzma
if ($payload ne "")
{
    if($xz_compression)
    {
        run_command("xz -fk --stdout --check=crc32 $payload > "
            . "$payload.bin");
    }
    else
    {
        run_command("cp $payload $payload.bin");
    }
}

sub processConvergedSections {

    # Source and destination file for each supported section
    my %sections=();
    $sections{HBB}{in}   = "$hb_image_dir/img/hostboot.bin";
    $sections{HBB}{out}  = "$scratch_dir/hostboot.header.bin.ecc";
    $sections{HBI}{in}   = "$hb_image_dir/img/hostboot_extended.bin";
    $sections{HBI}{out}  = "$scratch_dir/hostboot_extended.header.bin.ecc";
    $sections{HBD}{in}   = "$op_target_dir/$targeting_binary_source";
    $sections{HBD}{out}  = "$scratch_dir/$targeting_binary_filename";
    $sections{SBE}{in}   = "$hb_binary_dir/$sbe_binary_filename";
    $sections{SBE}{out}  = "$scratch_dir/$sbe_binary_filename";
    $sections{SBEC}{in}  = "$hb_binary_dir/$sbec_binary_filename";
    $sections{SBEC}{out} = "$scratch_dir/$sbec_binary_filename";
    $sections{PAYLOAD}{in}  = "$payload.bin";
    $sections{PAYLOAD}{out} = "$scratch_dir/$payload_filename";

    # Build up the system bin files specification
    my $system_bin_files;
    foreach my $section (keys %sections)
    {
        $_ = $sections{$section}{in};
        if((/ecc/i) || (/pad/i))
        {
            die "Input file's name, $sections{$section}{in}, suggests padding "
                . "or ECC, neither of which is allowed.";
        }

        # Stage the input file
        run_command("cp $sections{$section}{in} "
            . "$scratch_dir/$section.staged");

        # If secureboot compile, there can be extra protected
        # and unprotected versions of the input to stage
        if(-e "$sections{$section}{in}.protected")
        {
            run_command("cp $sections{$section}{in}.protected "
                . "$scratch_dir/$section.staged.protected");
        }

        if(-e "$sections{$section}{in}.unprotected")
        {
            run_command("cp $sections{$section}{in}.unprotected "
                . "$scratch_dir/$section.staged.unprotected");
        }

        # Build up the systemBinFiles argument
        my $separator = length($system_bin_files) ? "," : "";
        $system_bin_files .= "$separator$section=$scratch_dir/"
            . "$section.staged";
    }

    if(length($system_bin_files))
    {
        # Direct the tooling to use the open signing tools, if secureboot
        # enabled
        if($secureboot)
        {
            $ENV{'DEV_KEY_DIR'}="$ENV{'HOST_DIR'}/etc/keys/";
            $ENV{'SIGNING_DIR'} = "$ENV{'HOST_DIR'}/usr/bin/";
            $ENV{'SIGNING_TOOL_EDITION'} = "community";
        }

        # Determine whether to securely sign the images
        my $securebootArg = $secureboot ? "--secureboot" : "";

        # Process each image
        my $cmd =   "cd $scratch_dir && "
                  . "$hb_image_dir/genPnorImages.pl "
                      . "--binDir $scratch_dir "
                      . "--systemBinFiles $system_bin_files "
                      . "--pnorLayout $pnor_layout "
                      . "$securebootArg ";

        # Print context not visible in the actual command
        if($debug)
        {
            print STDOUT "SIGNING_DIR: " . $ENV{'SIGNING_DIR'} . "\n";
            print STDOUT "DEV_KEY_DIR: " . $ENV{'DEV_KEY_DIR'} . "\n";
            print STDOUT "SIGNING_TOOL_EDITION: "
                . $ENV{'SIGNING_TOOL_EDITION'} . "\n";
        }

        run_command($cmd);

        # Copy each output file to its final destination
        foreach my $section (keys %sections)
        {
            run_command("cp $scratch_dir/$section.bin "
                . "$sections{$section}{out}");
        }
    }
}

processConvergedSections();

run_command("env echo -en VERSION\\\\0 > $scratch_dir/hostboot_runtime.sha.bin");
run_command("sha512sum $hb_image_dir/img/hostboot_runtime.bin | awk \'{print \$1}\' | xxd -pr -r >> $scratch_dir/hostboot_runtime.sha.bin");
run_command("dd if=$scratch_dir/hostboot_runtime.sha.bin of=$scratch_dir/hostboot.temp.bin ibs=4k conv=sync");
run_command("cat $hb_image_dir/img/hostboot_runtime.bin >> $scratch_dir/hostboot.temp.bin");
run_command("dd if=$scratch_dir/hostboot.temp.bin of=$scratch_dir/hostboot_runtime.header.bin ibs=3072K conv=sync");
run_command("ecc --inject $scratch_dir/hostboot_runtime.header.bin --output $scratch_dir/hostboot_runtime.header.bin.ecc --p8");

#Create blank binary file for HB Errorlogs (HBEL) Partition
run_command("dd if=/dev/zero bs=128K count=1 | tr \"\\000\" \"\\377\" > $scratch_dir/hostboot.temp.bin");
run_command("ecc --inject $scratch_dir/hostboot.temp.bin --output $scratch_dir/hbel.bin.ecc --p8");\

#Create blank binary file for GUARD Data (GUARD) Partition
run_command("dd if=/dev/zero bs=16K count=1 | tr \"\\000\" \"\\377\" > $scratch_dir/hostboot.temp.bin");
run_command("ecc --inject $scratch_dir/hostboot.temp.bin --output $scratch_dir/guard.bin.ecc --p8");

#Create blank binary file for NVRAM Data (NVRAM) Partition
run_command("dd if=/dev/zero bs=512K count=1 of=$scratch_dir/nvram.bin");

#Create blank binary file for MVPD Partition
run_command("dd if=/dev/zero bs=512K count=1 | tr \"\\000\" \"\\377\" > $scratch_dir/hostboot.temp.bin");
run_command("ecc --inject $scratch_dir/hostboot.temp.bin --output $scratch_dir/mvpd_fill.bin.ecc --p8");

#Create blank binary file for DJVPD Partition
run_command("dd if=/dev/zero bs=256K count=1 | tr \"\\000\" \"\\377\" > $scratch_dir/hostboot.temp.bin");
run_command("ecc --inject $scratch_dir/hostboot.temp.bin --output $scratch_dir/djvpd_fill.bin.ecc --p8");

#Add ECC Data to CVPD Data Partition
run_command("dd if=$hb_binary_dir/cvpd.bin of=$scratch_dir/hostboot.temp.bin ibs=256K conv=sync");
run_command("ecc --inject $scratch_dir/hostboot.temp.bin --output $scratch_dir/cvpd.bin.ecc --p8");

#Create blank binary file for ATTR_TMP Partition
run_command("dd if=/dev/zero bs=28K count=1 | tr \"\\000\" \"\\377\" > $scratch_dir/hostboot.temp.bin");
run_command("ecc --inject $scratch_dir/hostboot.temp.bin --output $scratch_dir/attr_tmp.bin.ecc --p8");

#Create blank binary file for ATTR_PERM Partition
run_command("dd if=/dev/zero bs=28K count=1 | tr \"\\000\" \"\\377\" > $scratch_dir/hostboot.temp.bin");
run_command("ecc --inject $scratch_dir/hostboot.temp.bin --output $scratch_dir/attr_perm.bin.ecc --p8");

#Create blank binary file for OCC Partition
run_command("dd if=$occ_binary_filename of=$scratch_dir/hostboot.temp.bin ibs=1M conv=sync");
run_command("ecc --inject $scratch_dir/hostboot.temp.bin --output $occ_binary_filename.ecc --p8");

#Encode Ecc into CAPP Partition
run_command("dd if=$capp_binary_filename bs=144K count=1 > $scratch_dir/hostboot.temp.bin");
run_command("ecc --inject $scratch_dir/hostboot.temp.bin --output $scratch_dir/cappucode.bin.ecc --p8");

#Create blank binary file for FIRDATA Partition
run_command("dd if=/dev/zero bs=8K count=1 | tr \"\\000\" \"\\377\" > $scratch_dir/hostboot.temp.bin");
run_command("ecc --inject $scratch_dir/hostboot.temp.bin --output $scratch_dir/firdata.bin.ecc --p8");

#Create blank binary file for SECBOOT Partition
run_command("dd if=/dev/zero bs=128K count=1 > $scratch_dir/hostboot.temp.bin");
run_command("ecc --inject $scratch_dir/hostboot.temp.bin --output $scratch_dir/secboot.bin.ecc --p8");

#Add openpower version file
run_command("dd if=$openpower_version_filename of=$scratch_dir/openpower_version.temp ibs=4K conv=sync");
run_command("cp $scratch_dir/openpower_version.temp $openpower_version_filename");

#Copy Binary Data files for consistency
run_command("cp $hb_binary_dir/$wink_binary_filename $scratch_dir/");

#END MAIN
#-------------------------------------------------------------------------





############# HELPER FUNCTIONS #################################################
# Function to first print, and then run a system command, erroring out if the
#  command does not complete successfully
sub run_command {
    my $command = shift;
    print "$command\n";
    my $rc = system($command);
    if ($rc !=0 ){
        die "Error running command: $command. Nonzero return code of ($rc) returned.\n";
    }
    return $rc;
}

# Function to remove leading and trailing whitespeace before returning that string
sub trim_string {
    my $str = shift;
    $str =~ s/^\s+//;
    $str =~ s/\s+$//;
    return $str;
}
