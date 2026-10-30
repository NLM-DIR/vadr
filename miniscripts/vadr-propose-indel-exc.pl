#!/usr/bin/env perl
#
# vadr-propose-indel-exc.pl: propose insertn_mdl_exc/deletin_mdl_exc
# exception values for a VADR model info file, from v-annotate.pl
# output on a set of trusted sequences (brief 26_0602-055).
#
# Three modes:
#
#  convert: re-key the legacy insertn_exc/deletin_exc values (matched
#           on an approximate, protein-derived model position by
#           insertnp/deletinp) to insertn_mdl_exc/deletin_mdl_exc
#           values (matched on the exact, alignment-derived model
#           position). Needs v-annotate.pl --out_idl output on
#           sequences annotated with the input model info file.
#           For each feature with a legacy value:
#            - a point value at each exact position of a protein-based
#              indel that a legacy value exempted, with that legacy
#              value's maximum;
#            - every legacy segment that exempted a nucleotide-based
#              (insertnn/deletinn) indel, kept as is (these alerts
#              always matched on the exact position);
#            - every legacy segment that exempted nothing in the input,
#              kept as is (unless --drop_unused).
#           Where two of these set the same position, the larger
#           maximum is used.
#
#  extend:  add insertn_mdl_exc/deletin_mdl_exc values for the fatal
#           insertnp/deletinp alerts reported (.alt) for trusted
#           sequences: a point value at the alert's exact model
#           position, with maximum the longest such indel there.
#           Existing values are never lowered or removed. By default
#           only sequences whose fatal alerts are all insertnp/deletinp
#           are used (they would pass if exempted), see --allseqs.
#           Features with a legacy insertn_exc/deletin_exc key are
#           skipped: run convert first.
#
#  compare: report sequences that change between PASS and FAIL from
#           one set of v-annotate.pl output directories to another,
#           with their fatal alerts; used to check held-out folds
#           written with --cv.
#
use strict;
use warnings;
use Getopt::Long;
require "sqp_utils.pm";
require "sqp_ofile.pm";
require "vadr.pm";

my $usage;
$usage  = "vadr-propose-indel-exc.pl: propose insertn_mdl_exc/deletin_mdl_exc values from v-annotate.pl output\n\n";
$usage .= "Usage:\n";
$usage .= "  vadr-propose-indel-exc.pl [OPTIONS] convert <in.minfo> <out root> <v-annotate output dir 1> [<dir 2> ...]\n";
$usage .= "  vadr-propose-indel-exc.pl [OPTIONS] extend  <in.minfo> <out root> <v-annotate output dir 1> [<dir 2> ...]\n";
$usage .= "  vadr-propose-indel-exc.pl [OPTIONS] compare <out root> <dir A1>[,<dir A2>...] <dir B1>[,<dir B2>...]\n\n";
$usage .= "  convert needs v-annotate.pl output created with --out_idl (.idl files)\n";
$usage .= "  extend and compare use the .alt and .sqc files\n\n";
$usage .= "  Output (convert/extend): <out root>.minfo (input file with only the four indel exception keys changed),\n";
$usage .= "                          <out root>.exc.tsv (one line per value: origin and what it exempts in the input)\n";
$usage .= "  Output (compare):        <out root>.flips.tsv\n\n";
$usage .= "  OPTIONS:\n";
$usage .= "    --seqlist <f>   : only use sequences listed in <f> (the trusted set; one name per line)\n";
$usage .= "    --drop_unused   : convert: drop legacy values that exempted nothing in the input\n";
$usage .= "    --allseqs       : extend: also use sequences with fatal alerts other than insertnp/deletinp\n";
$usage .= "    --xmaxins <n>   : default maximum insertnp length used by v-annotate.pl [27]\n";
$usage .= "    --xmaxdel <n>   : default maximum deletinp length used by v-annotate.pl [27]\n";
$usage .= "    --nmaxins <n>   : default maximum insertnn length used by v-annotate.pl [27]\n";
$usage .= "    --nmaxdel <n>   : default maximum deletinn length used by v-annotate.pl [27]\n";
$usage .= "    --cv <n>        : convert/extend: also write <n> held-out folds: <out root>.cv<i>.minfo derived\n";
$usage .= "                      without fold <i>, and <out root>.cv<i>.list, the sequences of fold <i>\n";
$usage .= "    --seed <n>      : with --cv, seed for assigning sequences to folds [181]\n";
$usage .= "    --folds <f>     : with --cv, read fold assignments from <f> (<seqname> <fold> per line) instead\n";

my $opt_seqlist     = undef;
my $opt_drop_unused = 0;
my $opt_allseqs     = 0;
my %dflt_H          = ("insertnp" => 27, "deletinp" => 27, "insertnn" => 27, "deletinn" => 27);
my $opt_cv          = undef;
my $opt_seed        = 181;
my $opt_folds       = undef;
&GetOptions("seqlist=s"   => \$opt_seqlist,
            "drop_unused" => \$opt_drop_unused,
            "allseqs"     => \$opt_allseqs,
            "xmaxins=i"   => \$dflt_H{"insertnp"},
            "xmaxdel=i"   => \$dflt_H{"deletinp"},
            "nmaxins=i"   => \$dflt_H{"insertnn"},
            "nmaxdel=i"   => \$dflt_H{"deletinn"},
            "cv=i"        => \$opt_cv,
            "seed=i"      => \$opt_seed,
            "folds=s"     => \$opt_folds) || die $usage;

if(scalar(@ARGV) < 1) { die $usage; }
my $mode = shift @ARGV;

my %class_H   = ("insertnp" => "ins", "insertnn" => "ins", "deletinp" => "del", "deletinn" => "del"); # alert code -> indel class
my %legkey_H  = ("ins" => "insertn_exc",     "del" => "deletin_exc");      # legacy key per indel class
my %mdlkey_H  = ("ins" => "insertn_mdl_exc", "del" => "deletin_mdl_exc");  # recommended key per indel class

if($mode eq "compare") {
  if(scalar(@ARGV) != 3) { die $usage; }
  my ($out_root, $dirsA, $dirsB) = @ARGV;
  my $keep_HR = (defined $opt_seqlist) ? read_list($opt_seqlist) : undef;
  compare_runs($out_root, [split(",", $dirsA)], [split(",", $dirsB)], $keep_HR);
  exit 0;
}
if((($mode ne "convert") && ($mode ne "extend")) || (scalar(@ARGV) < 3)) { die $usage; }
if((defined $opt_folds) && (! defined $opt_cv)) { die "ERROR, --folds requires --cv"; }
my ($in_minfo, $out_root, @dir_A) = @ARGV;

# read the model info file, the input runs, and the trusted set
my %minfo_H = ();
read_minfo($in_minfo, \%minfo_H);
my %run_H = ();
read_runs(\@dir_A, ($mode eq "convert") ? 2 : 1, \%run_H); # .idl required for convert, read if present for extend
my $trusted_HR = (defined $opt_seqlist) ? read_list($opt_seqlist) : undef;
my @seq_A = grep { (! defined $trusted_HR) || (defined $trusted_HR->{$_}) } @{$run_H{"seq_A"}};
if(scalar(@seq_A) == 0) { die "ERROR, no sequences to use (check --seqlist names against the .sqc files)"; }

# derive on all trusted sequences, write the model info file and the report
my %use_H = map { $_ => 1 } @seq_A;
my ($new_HR, $origin_HR, $info_HR) = derive(\%use_H);
write_minfo(\%minfo_H, $new_HR, $out_root . ".minfo");
write_report(\%minfo_H, $new_HR, $origin_HR, \%use_H, $out_root . ".exc.tsv");
printf("%s: %d sequences used (%d input), %d values in %d feature/key pairs (%d before)\n",
       $mode, scalar(@seq_A), scalar(@{$run_H{"seq_A"}}), nvalues($new_HR), scalar(keys %{$new_HR}), nvalues_in($info_HR->{"before"}));
foreach my $k (sort keys %{$info_HR->{"counts"}}) { printf("  %-30s %d\n", $k, $info_HR->{"counts"}{$k}); }
printf("Wrote %s.minfo and %s.exc.tsv\n", $out_root, $out_root);

# held-out folds
if(defined $opt_cv) {
  my %fold_H = ();
  assign_folds(\@seq_A, $opt_cv, $opt_seed, $opt_folds, \%fold_H);
  for(my $i = 1; $i <= $opt_cv; $i++) {
    my %train_H = map { $_ => 1 } grep { $fold_H{$_} != $i } @seq_A;
    my ($cv_new_HR, undef, undef) = derive(\%train_H);
    write_minfo(\%minfo_H, $cv_new_HR, $out_root . ".cv" . $i . ".minfo");
    open(my $lfh, ">", $out_root . ".cv" . $i . ".list") || die "ERROR, unable to open $out_root.cv$i.list for writing";
    foreach my $s (grep { $fold_H{$_} == $i } @seq_A) { print $lfh "$s\n"; }
    close($lfh);
    printf("cv fold %d: derived from %d sequences, %d values; held out %d sequences: %s.cv%d.minfo, %s.cv%d.list\n",
           $i, scalar(keys %train_H), nvalues($cv_new_HR), scalar(@seq_A) - scalar(keys %train_H), $out_root, $i, $out_root, $i);
  }
}
exit 0;

#################################################################
# Subroutine: read_minfo()
# Incept:     EPN, Fri Oct 30 2026 (w/Claude)
# Purpose:    Read a model info file: keep its lines, and for each
#             FEATURE line its model, feature index, strand, name, and
#             the values of its four indel exception keys, parsed as
#             v-annotate.pl does (';' read as ',', overlapping
#             segments are an error).
# Returns:    void, fills %{$minfo_HR}
#################################################################
sub read_minfo {
  my ($file, $minfo_HR) = @_;
  open(my $fh, "<", $file) || die "ERROR, unable to open model info file $file for reading";
  my @line_A = <$fh>;
  close($fh);
  chomp(@line_A);
  $minfo_HR->{"line_A"} = \@line_A;
  $minfo_HR->{"ftr_HH"} = {}; # key: "<model>:<ftr_idx>"
  my $mdl = undef;
  my $ftr_idx = -1;
  for(my $i = 0; $i < scalar(@line_A); $i++) {
    my $line = $line_A[$i];
    if($line =~ /^MODEL\s+(\S+)/) { $mdl = $1; $ftr_idx = -1; next; }
    if($line !~ /^FEATURE\s+(\S+)/) { next; }
    if((! defined $mdl) || ($1 ne $mdl)) { die "ERROR, FEATURE line for a model other than the preceding MODEL line in $file:\n$line"; }
    $ftr_idx++;
    my %ftr = ("line" => $i, "mdl" => $mdl, "idx" => $ftr_idx);
    my ($coords) = ($line =~ /\scoords:"([^"]*)"/);
    if(! defined $coords) { die "ERROR, FEATURE line without coords in $file:\n$line"; }
    my %strand_H = map { $_ => 1 } ($coords =~ /:([\+\-])/g);
    $ftr{"strand"} = (scalar(keys %strand_H) == 1) ? (keys %strand_H)[0] : "mixed";
    my ($type) = ($line =~ /\stype:"([^"]*)"/);
    my ($name) = ($line =~ /\sproduct:"([^"]*)"/);
    if(! defined $name) { ($name) = ($line =~ /\sgene:"([^"]*)"/); }
    $ftr{"name"} = (defined $name) ? $name : ((defined $type) ? $type : "-");
    $ftr{"name"} =~ s/\s/\_/g;
    foreach my $old_key ("nmaxins_exc", "nmaxdel_exc", "xmaxins_exc", "xmaxdel_exc") {
      if($line =~ /\s$old_key:"/) { die "ERROR, feature $ftr_idx of model $mdl uses the pre-1.6 key $old_key; update the model info file to the current keys first"; }
    }
    foreach my $c ("ins", "del") {
      my $nkey = 0;
      foreach my $key ($legkey_H{$c}, $mdlkey_H{$c}) {
        if($line =~ /\s$key:"([^"]*)"/) {
          my $value = $1;
          $nkey++;
          $value =~ s/\;/\,/g; # as vdr_BackwardsCompatibilityExceptions()
          $value =~ s/\,$//;
          my %sgm_H  = ();
          my %posn_H = ();
          vdr_ExceptionCoordsAndValuesToSegmentsAndValues($value, "feature $ftr_idx of model $mdl, key $key", \%sgm_H, undef);
          vdr_ExceptionSegmentsAndValuesToPositionsAndValues(\%sgm_H, 0, \%posn_H, undef);
          my %pos2sgm_H = (); # position -> segment that contains it
          foreach my $sgm (keys %sgm_H) { 
            my %one_H = ();
            vdr_ExceptionOneSegmentAndValueToPositionsAndValues($sgm, $sgm_H{$sgm}, 0, \%one_H, undef);
            foreach my $pos (keys %one_H) { $pos2sgm_H{$pos} = $sgm; }
          }
          $ftr{$c} = { "key" => $key, "sgm_H" => \%sgm_H, "posn_H" => \%posn_H, "pos2sgm_H" => \%pos2sgm_H, "legacy" => ($key eq $legkey_H{$c}) ? 1 : 0 };
        }
      }
      if($nkey > 1) { die "ERROR, feature $ftr_idx of model $mdl defines both $legkey_H{$c} and $mdlkey_H{$c}"; }
    }
    $minfo_HR->{"ftr_HH"}{"$mdl:$ftr_idx"} = \%ftr;
  }
  return;
}

#################################################################
# Subroutine: read_runs()
# Incept:     EPN, Fri Oct 30 2026 (w/Claude)
# Purpose:    Read the .sqc (pass/fail), .alt (fatal alerts) and the
#             .idl (--out_idl) file of each v-annotate.pl output
#             directory: $need_idl is 2 if the .idl is required, 1 to
#             read it if it exists, 0 to not read it.
# Returns:    void, fills %{$run_HR}
#################################################################
sub read_runs {
  my ($dir_AR, $need_idl, $run_HR) = @_;
  $run_HR->{"seq_A"}   = [];
  $run_HR->{"pf_H"}    = {}; # seq -> PASS/FAIL
  $run_HR->{"fatal_HA"} = {}; # seq -> array of [code, mdl, ftr_idx, mpos, len] for fatal alerts
  $run_HR->{"idl_A"}   = []; # array of [seq, mdl, ftr_idx, code, hit, len, apos, epos, max, key, if_rep]
  foreach my $dir (@{$dir_AR}) {
    $dir =~ s/\/$//;
    my $base = $dir; $base =~ s/^.*\///;
    my $root = "$dir/$base.vadr";
    read_sqc_and_alt($root, $run_HR);
    my $idl_file = "$root.idl";
    if(($need_idl == 2) && (! -e $idl_file)) { die "ERROR, $idl_file does not exist; run v-annotate.pl with --out_idl"; }
    if(($need_idl > 0) && (-e $idl_file)) {
      open(my $fh, "<", $idl_file) || die "ERROR, unable to open $idl_file for reading";
      while(my $line = <$fh>) {
        if($line =~ /^\#/ || $line !~ /\S/) { next; }
        my @el_A = split(/\s+/, $line);
        if(scalar(@el_A) != 14) { die "ERROR, unable to parse line in $idl_file (expected 14 fields):\n$line"; }
        my (undef, $seq, $mdl, undef, undef, $ftr_idx, $code, $hit, $len, $apos, $epos, $max, $key, $if_rep) = @el_A;
        push(@{$run_HR->{"idl_A"}}, [$seq, $mdl, $ftr_idx-1, $code, $hit, $len, $apos, $epos, $max, $key, $if_rep]);
      }
      close($fh);
    }
  }
  return;
}

#################################################################
# Subroutine: read_sqc_and_alt()
# Incept:     EPN, Fri Oct 30 2026 (w/Claude)
# Purpose:    Read pass/fail from <root>.sqc and fatal alerts from
#             <root>.alt into %{$run_HR}.
# Returns:    void
#################################################################
sub read_sqc_and_alt {
  my ($root, $run_HR) = @_;
  foreach my $sfx (".sqc", ".alt") {
    if(! -e "$root$sfx") { die "ERROR, $root$sfx does not exist"; }
  }
  open(my $fh, "<", "$root.sqc") || die "ERROR, unable to open $root.sqc for reading";
  while(my $line = <$fh>) {
    if($line =~ /^\#/ || $line !~ /\S/) { next; }
    my @el_A = split(/\s+/, $line);
    my ($seq, $pf) = ($el_A[1], $el_A[3]);
    if(defined $run_HR->{"pf_H"}{$seq}) { die "ERROR, sequence $seq is in more than one input .sqc file"; }
    $run_HR->{"pf_H"}{$seq} = $pf;
    push(@{$run_HR->{"seq_A"}}, $seq);
  }
  close($fh);
  open($fh, "<", "$root.alt") || die "ERROR, unable to open $root.alt for reading";
  while(my $line = <$fh>) {
    if($line =~ /^\#/ || $line !~ /\S/) { next; }
    chomp $line;
    my @el_A = split(/\s+/, $line, 14);
    my ($seq, $mdl, $ftr_idx, $code, $fail, $mcoords, $detail) = @el_A[1, 2, 5, 6, 7, 11, 13];
    if($fail ne "yes") { next; }
    my ($mpos) = ($mcoords =~ /^(\d+)\.\./);
    my ($len)  = ($detail  =~ /(\d+)\>\d+\]$/);
    push(@{$run_HR->{"fatal_HA"}{$seq}}, [$code, $mdl, ($ftr_idx eq "-") ? -1 : $ftr_idx-1, $mpos, $len]);
  }
  close($fh);
  return;
}

#################################################################
# Subroutine: derive()
# Incept:     EPN, Fri Oct 30 2026 (w/Claude)
# Purpose:    Derive new exception values ($mode convert or extend)
#             from the sequences in %{$use_HR}.
# Returns:    three hash refs:
#             new values:  "<mdl>:<ftr_idx>:<class>" -> {position -> max}
#             origins:     same keys -> {position -> {origin -> 1}}
#             info:        {"counts" -> {...}, "before" -> {...}}
#################################################################
sub derive {
  my ($use_HR) = @_;
  my %new_HH = ();
  my %origin_HHH = ();
  my %counts_H = ();
  my %before_HH = ();
  my $ftr_HHR = $minfo_H{"ftr_HH"};
  my $put = sub {
    my ($fk, $pos, $max, $origin) = @_;
    if((! defined $new_HH{$fk}{$pos}) || ($new_HH{$fk}{$pos} < $max)) { $new_HH{$fk}{$pos} = $max; }
    $origin_HHH{$fk}{$pos}{$origin} = 1;
  };
  foreach my $mf (keys %{$ftr_HHR}) {
    foreach my $c ("ins", "del") {
      if(defined $ftr_HHR->{$mf}{$c}) { $before_HH{"$mf:$c"} = $ftr_HHR->{$mf}{$c}{"posn_H"}; }
    }
  }

  if($mode eq "convert") {
    my %used_H = (); # "<mdl>:<ftr_idx>:<class>:<segment>" -> 1 for legacy segments that exempted something
    my %ntkeep_H = ();
    foreach my $t (@{$run_H{"idl_A"}}) {
      my ($seq, $mdl, $ftr_idx, $code, $hit, $len, $apos, $epos, $max, $key, $if_rep) = @{$t};
      if(! defined $use_HR->{$seq}) { next; }
      my $c = $class_H{$code};
      my $ftr_HR = $ftr_HHR->{"$mdl:$ftr_idx"};
      if(! defined $ftr_HR) { die "ERROR, .idl line for feature " . ($ftr_idx+1) . " of model $mdl, which is not in $in_minfo"; }
      if((! defined $ftr_HR->{$c}) || (! $ftr_HR->{$c}{"legacy"})) { next; }
      my $is_nt = ($code =~ /nn$/) ? 1 : 0;
      my $lpos = ($is_nt) ? $epos : $apos; # legacy keys match nucleotide-based alerts on the exact position
      my $lmax = (($lpos ne "-") && (defined $ftr_HR->{$c}{"posn_H"}{$lpos})) ? $ftr_HR->{$c}{"posn_H"}{$lpos} : $dflt_H{$code};
      if($lmax != $max) { $counts_H{"lines whose max differs from input model info"}++; }
      if($len > $lmax) { next; } # not exempted by a legacy value
      my $sgm = $ftr_HR->{$c}{"pos2sgm_H"}{$lpos};
      $used_H{"$mdl:$ftr_idx:$c:$sgm"} = 1;
      if($is_nt) {
        $ntkeep_H{"$mdl:$ftr_idx:$c:$sgm"} = 1;
      }
      elsif($epos eq "-") {
        $counts_H{"exempted indels w/o exact position (skipped)"}++;
      }
      else {
        $put->("$mdl:$ftr_idx:$c", $epos, $lmax, "converted");
      }
    }
    foreach my $mf (sort keys %{$ftr_HHR}) {
      foreach my $c ("ins", "del") {
        my $ftr_HR = $ftr_HHR->{$mf};
        if((! defined $ftr_HR->{$c}) || (! $ftr_HR->{$c}{"legacy"})) { next; }
        $counts_H{"features converted ($c)"}++;
        $new_HH{"$mf:$c"} = {} if(! defined $new_HH{"$mf:$c"});
        foreach my $sgm (sort keys %{$ftr_HR->{$c}{"sgm_H"}}) {
          my $origin = undef;
          if(defined $ntkeep_H{"$mf:$c:$sgm"})  { $origin = "nt_kept"; $counts_H{"legacy segments kept for insertnn/deletinn"}++; }
          elsif(! defined $used_H{"$mf:$c:$sgm"}) {
            $counts_H{"legacy segments unused in input"}++;
            if(! $opt_drop_unused) { $origin = "unused_kept"; }
          }
          if(defined $origin) {
            my %posn_H = ();
            vdr_ExceptionOneSegmentAndValueToPositionsAndValues($sgm, $ftr_HR->{$c}{"sgm_H"}{$sgm}, 0, \%posn_H, undef);
            foreach my $pos (keys %posn_H) { $put->("$mf:$c", $pos, $posn_H{$pos}, $origin); }
          }
        }
      }
    }
  }
  else { # extend
    foreach my $mf (keys %{$ftr_HHR}) {
      foreach my $c ("ins", "del") {
        my $ftr_HR = $ftr_HHR->{$mf};
        if((defined $ftr_HR->{$c}) && (! $ftr_HR->{$c}{"legacy"})) {
          foreach my $pos (keys %{$ftr_HR->{$c}{"posn_H"}}) { $put->("$mf:$c", $pos, $ftr_HR->{$c}{"posn_H"}{$pos}, "existing"); }
        }
      }
    }
    foreach my $seq (@seq_A) {
      if((! defined $use_HR->{$seq}) || ($run_H{"pf_H"}{$seq} ne "FAIL")) { next; }
      my @fatal_A = @{$run_H{"fatal_HA"}{$seq}};
      my $nother = scalar(grep { ($_->[0] ne "insertnp") && ($_->[0] ne "deletinp") } @fatal_A);
      if(($nother > 0) && (! $opt_allseqs)) { $counts_H{"failing seqs skipped (other fatal alerts)"}++; next; }
      foreach my $a (@fatal_A) {
        my ($code, $mdl, $ftr_idx, $mpos, $len) = @{$a};
        if(($code ne "insertnp") && ($code ne "deletinp")) { next; }
        my $c = $class_H{$code};
        my $ftr_HR = $ftr_HHR->{"$mdl:$ftr_idx"};
        if(! defined $ftr_HR) { die "ERROR, .alt alert for feature " . ($ftr_idx+1) . " of model $mdl, which is not in $in_minfo"; }
        if((defined $ftr_HR->{$c}) && ($ftr_HR->{$c}{"legacy"})) { $counts_H{"alerts skipped (feature has legacy key, run convert)"}++; next; }
        if((! defined $mpos) || (! defined $len)) { die "ERROR, unable to parse model position and length of $code alert for $seq"; }
        my $fk = "$mdl:$ftr_idx:$c";
        my $cur = (defined $new_HH{$fk}{$mpos}) ? $new_HH{$fk}{$mpos} : $dflt_H{$code};
        if($len > $cur) { $counts_H{"alerts with a new or raised value"}++; }
        $put->($fk, $mpos, $len, ((defined $ftr_HR->{$c}) && (defined $ftr_HR->{$c}{"posn_H"}{$mpos})) ? "raised" : "new");
      }
      $counts_H{"failing seqs used"}++;
    }
  }
  # remove 'existing' origin where a value was raised
  foreach my $fk (keys %origin_HHH) {
    foreach my $pos (keys %{$origin_HHH{$fk}}) {
      if((defined $origin_HHH{$fk}{$pos}{"raised"}) && ($new_HH{$fk}{$pos} > $before_HH{$fk}{$pos})) { delete $origin_HHH{$fk}{$pos}{"existing"}; }
      elsif(defined $origin_HHH{$fk}{$pos}{"raised"}) { delete $origin_HHH{$fk}{$pos}{"raised"}; }
    }
  }
  return (\%new_HH, \%origin_HHH, { "counts" => \%counts_H, "before" => \%before_HH });
}

#################################################################
# Subroutine: positions_to_segments()
# Incept:     EPN, Fri Oct 30 2026 (w/Claude)
# Purpose:    Convert a position->max hash into a list of
#             [start, stop, max] segments, merging consecutive
#             positions with the same max, in the order of the
#             feature's strand.
#################################################################
sub positions_to_segments {
  my ($posn_HR, $strand) = @_;
  my @sgm_A = ();
  my @pos_A = sort { $a <=> $b } keys %{$posn_HR};
  if($strand eq "-") { @pos_A = reverse @pos_A; }
  my $step = ($strand eq "-") ? -1 : 1;
  foreach my $pos (@pos_A) {
    if((scalar(@sgm_A) > 0) && ($sgm_A[-1][1] + $step == $pos) && ($sgm_A[-1][2] == $posn_HR->{$pos})) {
      $sgm_A[-1][1] = $pos;
    }
    else {
      push(@sgm_A, [$pos, $pos, $posn_HR->{$pos}]);
    }
  }
  return @sgm_A;
}

#################################################################
# Subroutine: write_minfo()
# Incept:     EPN, Fri Oct 30 2026 (w/Claude)
# Purpose:    Write the model info file with new values: for each
#             feature/class in %{$new_HR}, the legacy key is replaced
#             in place by the recommended key, an existing recommended
#             key gets the new value, or the key is appended. All
#             other text is unchanged.
#################################################################
sub write_minfo {
  my ($minfo_HR, $new_HR, $file) = @_;
  my @line_A = @{$minfo_HR->{"line_A"}};
  foreach my $fk (sort keys %{$new_HR}) {
    my ($mdl, $ftr_idx, $c) = split(":", $fk);
    my $ftr_HR = $minfo_HR->{"ftr_HH"}{"$mdl:$ftr_idx"};
    if((scalar(keys %{$new_HR->{$fk}}) > 0) && ($ftr_HR->{"strand"} eq "mixed")) {
      die "ERROR, feature " . ($ftr_idx+1) . " of model $mdl has segments on both strands, not supported";
    }
    my $strand = $ftr_HR->{"strand"};
    my $value = join(",", map { sprintf("%d..%d:%s:%d", $_->[0], $_->[1], $strand, $_->[2]) } positions_to_segments($new_HR->{$fk}, $strand));
    my $i = $ftr_HR->{"line"};
    my $replaced = 0;
    foreach my $key ($legkey_H{$c}, $mdlkey_H{$c}) {
      if($line_A[$i] =~ /\s$key:"[^"]*"/) {
        if($value ne "") { $line_A[$i] =~ s/(\s)$key:"[^"]*"/$1$mdlkey_H{$c}:"$value"/; }
        else             { $line_A[$i] =~ s/\s$key:"[^"]*"//; }
        $replaced = 1;
      }
    }
    if((! $replaced) && ($value ne "")) { $line_A[$i] .= " " . $mdlkey_H{$c} . ":\"" . $value . "\""; }
  }
  open(my $fh, ">", $file) || die "ERROR, unable to open $file for writing";
  foreach my $line (@line_A) { print $fh $line . "\n"; }
  close($fh);
  return;
}

#################################################################
# Subroutine: write_report()
# Incept:     EPN, Fri Oct 30 2026 (w/Claude)
# Purpose:    Write one line per new exception value (segment): its
#             origin, and the input indels it exempts: all .idl lines
#             (every stored blastx hit, and nucleotide-based alerts,
#             which share the key) and the fatal .alt alerts it would
#             remove.
#################################################################
sub write_report {
  my ($minfo_HR, $new_HR, $origin_HR, $use_HR, $file) = @_;
  # index .idl lines and fatal alerts by feature/class
  my %idl_HA = ();
  foreach my $t (@{$run_H{"idl_A"}}) {
    my ($seq, $mdl, $ftr_idx, $code) = @{$t};
    if(defined $use_HR->{$seq}) { push(@{$idl_HA{"$mdl:$ftr_idx:" . $class_H{$code}}}, $t); }
  }
  my %alt_HA = ();
  foreach my $seq (keys %{$run_H{"fatal_HA"}}) {
    if(! defined $use_HR->{$seq}) { next; }
    foreach my $a (@{$run_H{"fatal_HA"}{$seq}}) {
      if(defined $class_H{$a->[0]}) { push(@{$alt_HA{"$a->[1]:$a->[2]:" . $class_H{$a->[0]}}}, [$seq, @{$a}]); }
    }
  }
  open(my $fh, ">", $file) || die "ERROR, unable to open $file for writing";
  print $fh join("\t", "model", "ftr_idx", "ftr_name", "key", "value", "origin",
                 "idl_lines_exempt", "idl_seqs_exempt", "longest_exempt", "fatal_alerts_removed", "seqs_alerts_removed", "example_seqs") . "\n";
  foreach my $fk (sort { my @a = split(":", $a); my @b = split(":", $b); ($a[0] cmp $b[0]) || ($a[1] <=> $b[1]) || ($a[2] cmp $b[2]) } keys %{$new_HR}) {
    my ($mdl, $ftr_idx, $c) = split(":", $fk);
    my $ftr_HR = $minfo_HR->{"ftr_HH"}{"$mdl:$ftr_idx"};
    foreach my $s (positions_to_segments($new_HR->{$fk}, $ftr_HR->{"strand"})) {
      my ($start, $stop, $max) = @{$s};
      my ($lo, $hi) = ($start <= $stop) ? ($start, $stop) : ($stop, $start);
      my %origin_H = ();
      for(my $p = $lo; $p <= $hi; $p++) { foreach my $o (keys %{$origin_HR->{$fk}{$p}}) { $origin_H{$o} = 1; } }
      my ($nidl, $longest, $nalt) = (0, 0, 0);
      my %idl_seq_H = (); my %alt_seq_H = ();
      foreach my $t (@{$idl_HA{$fk}}) {
        my $epos = $t->[7];
        if(($epos ne "-") && ($epos >= $lo) && ($epos <= $hi) && ($t->[5] <= $max)) {
          $nidl++; $idl_seq_H{$t->[0]} = 1; if($t->[5] > $longest) { $longest = $t->[5]; }
        }
      }
      foreach my $a (@{$alt_HA{$fk}}) {
        my ($seq, $code, undef, undef, $mpos, $len) = @{$a};
        if((defined $mpos) && ($mpos >= $lo) && ($mpos <= $hi) && ($len <= $max)) {
          $nalt++; $alt_seq_H{$seq} = 1; if($len > $longest) { $longest = $len; }
        }
      }
      my @ex_A = (sort keys %alt_seq_H, grep { ! defined $alt_seq_H{$_} } sort keys %idl_seq_H);
      print $fh join("\t", $mdl, $ftr_idx+1, $ftr_HR->{"name"}, $mdlkey_H{$c}, sprintf("%d..%d:%s:%d", $start, $stop, $ftr_HR->{"strand"}, $max),
                     join(",", sort keys %origin_H), $nidl, scalar(keys %idl_seq_H), $longest, $nalt, scalar(keys %alt_seq_H),
                     (scalar(@ex_A) > 0) ? join(",", @ex_A[0..(scalar(@ex_A) < 3 ? $#ex_A : 2)]) : "-") . "\n";
    }
  }
  close($fh);
  return;
}

#################################################################
# Subroutine: assign_folds()
# Incept:     EPN, Fri Oct 30 2026 (w/Claude)
# Purpose:    Assign each sequence to one of $k folds, randomly with
#             seed $seed (as even as possible), or from a file.
#################################################################
sub assign_folds {
  my ($seq_AR, $k, $seed, $file, $fold_HR) = @_;
  if(defined $file) {
    my %name2fold_H = ();
    my %fold_idx_H = ();
    open(my $fh, "<", $file) || die "ERROR, unable to open $file for reading";
    while(my $line = <$fh>) {
      if($line =~ /^\#/ || $line !~ /\S/) { next; }
      my ($seq, $fold) = split(/\s+/, $line);
      if(! defined $fold) { die "ERROR, unable to parse line in $file (expected <seqname> <fold>):\n$line"; }
      $name2fold_H{$seq} = $fold;
    }
    close($fh);
    my @label_A = sort { $a cmp $b } keys %{{ map { $_ => 1 } values %name2fold_H }};
    if(scalar(@label_A) != $k) { die sprintf("ERROR, %s has %d fold labels, --cv is %d", $file, scalar(@label_A), $k); }
    for(my $i = 0; $i < $k; $i++) { $fold_idx_H{$label_A[$i]} = $i+1; }
    foreach my $seq (@{$seq_AR}) {
      if(! defined $name2fold_H{$seq}) { die "ERROR, sequence $seq is not in $file"; }
      $fold_HR->{$seq} = $fold_idx_H{$name2fold_H{$seq}};
    }
    return;
  }
  srand($seed);
  my @shuf_A = sort @{$seq_AR};
  for(my $i = $#shuf_A; $i > 0; $i--) { my $j = int(rand($i+1)); @shuf_A[$i, $j] = @shuf_A[$j, $i]; }
  for(my $i = 0; $i < scalar(@shuf_A); $i++) { $fold_HR->{$shuf_A[$i]} = ($i % $k) + 1; }
  return;
}

#################################################################
# Subroutine: compare_runs()
# Incept:     EPN, Fri Oct 30 2026 (w/Claude)
# Purpose:    Report PASS->FAIL and FAIL->PASS sequences between two
#             sets of v-annotate.pl output directories, for sequences
#             in both (and in %{$keep_HR} if defined).
#################################################################
sub compare_runs {
  my ($out_root, $dirA_AR, $dirB_AR, $keep_HR) = @_;
  my %A = (); my %B = ();
  read_runs($dirA_AR, 0, \%A);
  read_runs($dirB_AR, 0, \%B);
  my @seq_A = grep { (defined $B{"pf_H"}{$_}) && ((! defined $keep_HR) || (defined $keep_HR->{$_})) } @{$A{"seq_A"}};
  my $nmiss = (defined $keep_HR) ? (scalar(keys %{$keep_HR}) - scalar(@seq_A)) : 0;
  my ($passA, $passB, $npf, $nfp) = (0, 0, 0, 0);
  my $fatal_str = sub {
    my ($R, $seq) = @_;
    my @str_A = map { sprintf("%s:%s@%s%s", $_->[0], ($_->[2] >= 0) ? $_->[2]+1 : "-", (defined $_->[3]) ? $_->[3] : "-", (defined $_->[4]) ? ":" . $_->[4] : "") } @{$R->{"fatal_HA"}{$seq} || []};
    return (scalar(@str_A) > 0) ? join(";", @str_A) : "-";
  };
  open(my $fh, ">", "$out_root.flips.tsv") || die "ERROR, unable to open $out_root.flips.tsv for writing";
  print $fh join("\t", "seq", "A", "B", "A_fatal", "B_fatal") . "\n";
  foreach my $seq (@seq_A) {
    my ($a, $b) = ($A{"pf_H"}{$seq}, $B{"pf_H"}{$seq});
    if($a eq "PASS") { $passA++; }
    if($b eq "PASS") { $passB++; }
    if($a ne $b) {
      if($a eq "PASS") { $npf++; } else { $nfp++; }
      print $fh join("\t", $seq, $a, $b, $fatal_str->(\%A, $seq), $fatal_str->(\%B, $seq)) . "\n";
    }
  }
  close($fh);
  printf("compare: %d sequences (%d listed but missing from a run), PASS %d -> %d, PASS->FAIL %d, FAIL->PASS %d\n",
         scalar(@seq_A), $nmiss, $passA, $passB, $npf, $nfp);
  printf("Wrote %s.flips.tsv\n", $out_root);
  return;
}

#################################################################
# small helpers
#################################################################
sub read_list {
  my ($file) = @_;
  my %H = ();
  open(my $fh, "<", $file) || die "ERROR, unable to open $file for reading";
  while(my $line = <$fh>) { if($line =~ /^(\S+)/) { $H{$1} = 1; } }
  close($fh);
  return \%H;
}
sub nvalues {
  my ($new_HR) = @_;
  my $n = 0;
  foreach my $fk (keys %{$new_HR}) {
    my ($mdl, $ftr_idx) = split(":", $fk);
    $n += scalar(positions_to_segments($new_HR->{$fk}, $minfo_H{"ftr_HH"}{"$mdl:$ftr_idx"}{"strand"}));
  }
  return $n;
}
sub nvalues_in {
  my ($before_HR) = @_;
  return nvalues($before_HR);
}
