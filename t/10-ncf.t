use strict;
use warnings FATAL => 'all';
use Test::More tests => 52;

BEGIN {
    use_ok( 'vadr' ) || print "Bail out!\n";
}

# make sure the VADRSCRIPTSDIR env variable is set
my $env_ok = exists $ENV{"VADRSCRIPTSDIR"} ? 1 : 0;
is($env_ok, 1, "VADRSCRIPTSDIR env variable set");

#######################################################
# non-coding feature (ncf) types and policies
#######################################################
my @ftr_info_AH = ();
my @types_A   = ("CDS", "gene", "mat_peptide", "5'UTR", "3'UTR", "operon", "stem_loop", "ncRNA", "regulatory", "primer_bind", "misc_feature", "repeat_region", "misc_structure");
my @exp_ncf_A = (0,     0,      0,             0,       0,       0,        1,           1,       1,            1,             1,              1,               1);
for(my $i = 0; $i < scalar(@types_A); $i++) {
  %{$ftr_info_AH[$i]} = ("type" => $types_A[$i]);
  is(vdr_FeatureTypeIsNcf(\@ftr_info_AH, $i), $exp_ncf_A[$i], "vdr_FeatureTypeIsNcf() correct for type $types_A[$i]");
}
is(vdr_NcfPolicyIsValid("fail"), 1, "fail is a valid ncf policy");
is(vdr_NcfPolicyIsValid("drop"), 1, "drop is a valid ncf policy");
is(vdr_NcfPolicyIsValid("misc"), 0, "misc is not a valid ncf policy");

# alert info for vdr_FeatureAlertCausesFailure() and vdr_FeatureAlertCausesDrop() checks
my %alt_info_HH = ();
vdr_AlertInfoInitialize(\%alt_info_HH, undef);
my $cds_idx = 0; # CDS
my $sl_idx  = 6; # stem_loop
vdr_FeatureInfoInitializeMiscNotFailure(\@ftr_info_AH, 0, undef);

# ncf policy not initialized: same as 'fail'
is(vdr_FeatureAlertNcfAction(\@ftr_info_AH, \%alt_info_HH, $sl_idx, "indf5gap"), "fail", "ncf action is fail for stem_loop if ncf policy not set");

# --ncf fail (default)
vdr_FeatureInfoInitializeNcfPolicy(\@ftr_info_AH, "fail", 0, undef);
is(vdr_FeatureAlertNcfAction(\@ftr_info_AH, \%alt_info_HH, $sl_idx, "indf5gap"), "fail", "--ncf fail: ncf action is fail for stem_loop");
is(vdr_FeatureAlertCausesFailure(\@ftr_info_AH, \%alt_info_HH, $sl_idx, "indf5gap"), 1, "--ncf fail: indf5gap causes failure for stem_loop");
is(vdr_FeatureAlertCausesDrop(\@ftr_info_AH, \%alt_info_HH, $sl_idx, "indf5gap"), 0, "--ncf fail: indf5gap does not cause drop for stem_loop");

# --ncf drop
vdr_FeatureInfoInitializeNcfPolicy(\@ftr_info_AH, "drop", 0, undef);
is(vdr_FeatureAlertNcfAction(\@ftr_info_AH, \%alt_info_HH, $sl_idx, "indf5gap"), "drop", "--ncf drop: ncf action is drop for stem_loop");
is(vdr_FeatureAlertNcfAction(\@ftr_info_AH, \%alt_info_HH, $cds_idx, "indf5gap"), "fail", "--ncf drop: ncf action is fail for CDS");
is(vdr_FeatureAlertCausesFailure(\@ftr_info_AH, \%alt_info_HH, $sl_idx, "indf5gap"), 0, "--ncf drop: indf5gap does not cause failure for stem_loop");
is(vdr_FeatureAlertCausesDrop(\@ftr_info_AH, \%alt_info_HH, $sl_idx, "indf5gap"), 1, "--ncf drop: indf5gap causes drop for stem_loop");
is(vdr_FeatureAlertCausesDrop(\@ftr_info_AH, \%alt_info_HH, $sl_idx, "ambgnt5f"), 0, "--ncf drop: ambgnt5f does not cause drop for stem_loop");
is(vdr_FeatureAlertCausesFailure(\@ftr_info_AH, \%alt_info_HH, $cds_idx, "indf5gap"), 1, "--ncf drop: indf5gap causes failure for CDS");
is(vdr_FeatureAlertCausesDrop(\@ftr_info_AH, \%alt_info_HH, $cds_idx, "indf5gap"), 0, "--ncf drop: indf5gap does not cause drop for CDS");

# --ncf drop, ncf_always_fail:"1" restores failure
$ftr_info_AH[$sl_idx]{"ncf_always_fail"} = "1";
is(vdr_FeatureAlertCausesFailure(\@ftr_info_AH, \%alt_info_HH, $sl_idx, "indf5gap"), 1, "--ncf drop: indf5gap causes failure for ncf_always_fail stem_loop");
is(vdr_FeatureAlertCausesDrop(\@ftr_info_AH, \%alt_info_HH, $sl_idx, "indf5gap"), 0, "--ncf drop: indf5gap does not cause drop for ncf_always_fail stem_loop");
$ftr_info_AH[$sl_idx]{"ncf_always_fail"} = "0";

# low similarity absorption and --mnf_legacy
is(vdr_FeatureAbsorbsLowSimilarity(\@ftr_info_AH, \%alt_info_HH, $cds_idx, "lowsim3c", 10, 30), 1, "--ncf drop: CDS absorbs low similarity region");
is(vdr_FeatureAbsorbsLowSimilarity(\@ftr_info_AH, \%alt_info_HH, $sl_idx,  "lowsim3n", 10, 30), 0, "--ncf drop: stem_loop does not absorb low similarity region");
$ftr_info_AH[$sl_idx]{"misc_not_failure"} = "1";
is(vdr_FeatureAbsorbsLowSimilarity(\@ftr_info_AH, \%alt_info_HH, $sl_idx,  "lowsim3n", 10, 30), 0, "--ncf drop: misc_not_failure stem_loop does not absorb low similarity region without --mnf_legacy");
vdr_FeatureInfoInitializeNcfPolicy(\@ftr_info_AH, "drop", 1, undef);
is(vdr_FeatureNcfMnfLegacy(\@ftr_info_AH, $sl_idx), 1, "--ncf drop --mnf_legacy: legacy behavior for misc_not_failure stem_loop");
is(vdr_FeatureNcfMnfLegacy(\@ftr_info_AH, $cds_idx), 0, "--ncf drop --mnf_legacy: no legacy behavior for CDS");
is(vdr_FeatureAbsorbsLowSimilarity(\@ftr_info_AH, \%alt_info_HH, $sl_idx,  "lowsim3n", 29, 30), 1, "--ncf drop --mnf_legacy: misc_not_failure stem_loop absorbs region shorter than long length");
is(vdr_FeatureAbsorbsLowSimilarity(\@ftr_info_AH, \%alt_info_HH, $sl_idx,  "lowsim3l", 30, 30), 0, "--ncf drop --mnf_legacy: misc_not_failure stem_loop does not absorb region of long length");
is(vdr_FeatureAlertCausesFailure(\@ftr_info_AH, \%alt_info_HH, $sl_idx, "lowsim3l"), 0, "--ncf drop --mnf_legacy: lowsim3l does not cause failure for misc_not_failure stem_loop");
is(vdr_FeatureAlertCausesDrop(\@ftr_info_AH, \%alt_info_HH, $sl_idx, "lowsim3n"), 1, "--ncf drop --mnf_legacy: lowsim3n causes drop for misc_not_failure stem_loop");
vdr_FeatureInfoInitializeNcfPolicy(\@ftr_info_AH, "fail", 1, undef);
is(vdr_FeatureNcfMnfLegacy(\@ftr_info_AH, $sl_idx), 0, "--ncf fail --mnf_legacy: no legacy behavior for misc_not_failure stem_loop");
is(vdr_FeatureAbsorbsLowSimilarity(\@ftr_info_AH, \%alt_info_HH, $sl_idx,  "lowsim3l", 30, 30), 1, "--ncf fail: misc_not_failure stem_loop absorbs region of long length");

#######################################################
# v-annotate.pl --ncf option and .minfo validation
#######################################################
my @cmd_A   = ();
my @desc_A  = ();
my @fail_A  = ();
my $base_cmd = "\$VADRSCRIPTSDIR/v-annotate.pl -f --pv_skip -m \$VADRSCRIPTSDIR/testfiles/models/entoy100a.cm";
my $fa       = "\$VADRSCRIPTSDIR/testfiles/entoy100a-lowsim.fa va-test-ncf > /dev/null 2>&1";

push(@cmd_A,  "$base_cmd --ncf misc -i \$VADRSCRIPTSDIR/testfiles/models/entoy100a.minfo $fa");
push(@desc_A, "v-annotate.pl --ncf with invalid value");
push(@fail_A, "1");

push(@cmd_A,  "$base_cmd --ncf drop -i \$VADRSCRIPTSDIR/testfiles/models/entoy100a-naf.minfo $fa");
push(@desc_A, "v-annotate.pl --ncf drop, ncf_always_fail on ncRNA and stem_loop");
push(@fail_A, "0");

push(@cmd_A,  "$base_cmd -i \$VADRSCRIPTSDIR/testfiles/models/entoy100a-naf-mnf.minfo $fa");
push(@desc_A, "v-annotate.pl ncf_always_fail and misc_not_failure on same ncRNA");
push(@fail_A, "1");

push(@cmd_A,  "$base_cmd --ignore_mnf -i \$VADRSCRIPTSDIR/testfiles/models/entoy100a-naf-mnf.minfo $fa");
push(@desc_A, "v-annotate.pl --ignore_mnf, ncf_always_fail and misc_not_failure on same ncRNA");
push(@fail_A, "0");

push(@cmd_A,  "$base_cmd -i \$VADRSCRIPTSDIR/testfiles/models/entoy100a-naf-cds.minfo $fa");
push(@desc_A, "v-annotate.pl ncf_always_fail on CDS");
push(@fail_A, "1");

push(@cmd_A,  "$base_cmd -i \$VADRSCRIPTSDIR/testfiles/models/entoy100a-ncfmnf.minfo $fa");
push(@desc_A, "v-annotate.pl misc_not_failure on stem_loop");
push(@fail_A, "0");

push(@cmd_A,  "$base_cmd --ncf drop -i \$VADRSCRIPTSDIR/testfiles/models/entoy100a-ncfmnf.minfo $fa");
push(@desc_A, "v-annotate.pl --ncf drop, misc_not_failure on stem_loop");
push(@fail_A, "1");

push(@cmd_A,  "$base_cmd --ncf drop --ignore_mnf -i \$VADRSCRIPTSDIR/testfiles/models/entoy100a-ncfmnf.minfo $fa");
push(@desc_A, "v-annotate.pl --ncf drop --ignore_mnf, misc_not_failure on stem_loop");
push(@fail_A, "0");

push(@cmd_A,  "$base_cmd --ncf drop --mnf_legacy -i \$VADRSCRIPTSDIR/testfiles/models/entoy100a-ncfmnf.minfo $fa");
push(@desc_A, "v-annotate.pl --ncf drop --mnf_legacy, misc_not_failure on stem_loop");
push(@fail_A, "0");

push(@cmd_A,  "$base_cmd --mnf_legacy -i \$VADRSCRIPTSDIR/testfiles/models/entoy100a-ncfmnf.minfo $fa");
push(@desc_A, "v-annotate.pl --mnf_legacy without --ncf drop, misc_not_failure on stem_loop");
push(@fail_A, "0");

my $ncmd = scalar(@cmd_A);
my $retval = undef;
for(my $i = 0; $i < $ncmd; $i++) {
  $retval = system($cmd_A[$i]);
  if($retval != 0) { $retval = 1; }
  is($retval, $fail_A[$i], sprintf("%s: expected %s", $desc_A[$i], ($fail_A[$i] ? "fail" : "return code 0 (pass)")));
}
system("rm -rf va-test-ncf");
