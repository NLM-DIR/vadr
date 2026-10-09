#!/usr/bin/env perl
# Usage (from testfiles/models/): perl make-NC_001959-vp2rev.pl NC_001959.fa
# Writes model files NC_001959-vp2rev.{fa,minfo,vadr.protein.fa} to the current
# directory and test sequence files noro.vp2rev.pvcoords.{1,2,3}.fa and
# noro.vp2only.pvcoords.4.fa to ../
# (then run makeblastdb, see update-blastdbs.sh, and esl-sfetch --index on the .fa).
#
# Build a reverse-complemented NC_001959 VP2-region model (negative strand CDS,
# with a blastx protein library) plus test sequences for blastx indel/end/strand
# alert sequence coordinates on a negative strand CDS.
use strict;
my $usage = "perl make-NC_001959-vp2rev.pl <NC_001959.fa>";
if(scalar(@ARGV) != 1) { die $usage; }
my $nc_fa = $ARGV[0];
open(IN, $nc_fa) || die "ERROR unable to open $nc_fa"; my $g = ""; while(<IN>) { next if /^>/; chomp; $g .= uc $_; } close IN;
my $rstart = 6501; my $rend = 7654;
my $fwd = substr($g, $rstart-1, $rend-$rstart+1);
my $L = length($fwd);
my $cds_s = 6950-$rstart+1; my $cds_e = 7588-$rstart+1;   # fwd-relative CDS, + strand
sub rc { my $s = reverse $_[0]; $s =~ tr/ACGT/TGCA/; return $s; }
my %c; my @b=qw(T C A G); my $aa="FFLLSSSSYY**CC*WLLLLPPPPHHQQRRRRIIIMTTTTNNKKSSRRVVVVAAAADDEEGGGG"; my $i=0;
for my $x (@b){for my $y (@b){for my $z (@b){$c{"$x$y$z"}=substr($aa,$i++,1);}}}
sub tr6 { my $s=shift; my $p=""; for(my $k=0;$k+3<=length($s);$k+=3){$p.=$c{substr($s,$k,3)};} return $p; }
sub wfa { my ($fh,$n,$s)=@_; print $fh ">$n\n"; for(my $k=0;$k<length($s);$k+=60){print $fh substr($s,$k,60),"\n";} }
my $cds = substr($fwd, $cds_s-1, $cds_e-$cds_s+1);
my $mdl = "NC_001959-vp2rev";
open(my $o, ">$mdl.fa"); wfa($o,$mdl,rc($fwd)); close $o;
my $rs = $L-$cds_s+1; my $re = $L-$cds_e+1;
printf STDERR ("model length $L, CDS $rs..$re:-, %d nt\n", $rs-$re+1);
open($o, ">$mdl.minfo");
print $o "MODEL $mdl blastdb:\"$mdl.vadr.protein.fa\" group:\"Norovirus\" length:\"$L\" subgroup:\"GI\"\n";
print $o "FEATURE $mdl type:\"CDS\" coords:\"$rs..$re:-\" parent_idx_str:\"GBNULL\" gene:\"ORF3\" product:\"VP2\"\n"; close $o;
my $prot = tr6($cds); $prot =~ s/\*$// || die "no stop"; die "internal stop" if $prot =~ /\*/;
open($o, ">$mdl.vadr.protein.fa"); wfa($o,"$mdl/$rs..$re:-",$prot); close $o;
# test seqs: mutate in fwd (CDS on +) orientation, then reverse complement
my $ins = "GCTGGTAAATCCGATCTGCAAGTTGCCACTGAG";  # 33 nt, 11 sense codons
die "stop in ins" if tr6($ins) =~ /\*/;
srand(7); my @nc = grep { $c{$_} ne "*" } sort keys %c;
sub rnd { my $n=shift; my $s=""; for(1..$n){ $s .= $nc[int(rand(scalar(@nc)))]; } return $s; }
sub ins_after { my ($k,$s)=@_; my $p=$cds_s-1+$k; return substr($fwd,0,$p).$s.substr($fwd,$p); } # insert after CDS nt k
sub del_at    { my ($k,$n)=@_; my $p=$cds_s-1+$k; return substr($fwd,0,$p).substr($fwd,$p+$n); } # delete n nt after CDS nt k
my %t;
$t{"vp2rev-ins3p"}   = ins_after(450, $ins);
$t{"vp2rev-del"}     = del_at(300, 36);
$t{"vp2rev-del5p"}   = del_at(15, 36);
$t{"vp2rev-trunc5p"} = substr($fwd,0,$cds_s-1+3) . rnd(20) . substr($fwd,$cds_s-1+63);   # codons 2..21 random
$t{"vp2rev-trunc3p"} = substr($fwd,0,$cds_e-63) . rnd(20) . substr($fwd,$cds_e-3);       # last 20 sense codons random
open($o, ">../noro.vp2rev.pvcoords.1.fa"); for my $n (sort keys %t) { wfa($o, $n, rc($t{$n})); } close $o;
# insert near CDS 5' end, in its own file (fatal error prior to fix)
open($o, ">../noro.vp2rev.pvcoords.2.fa"); wfa($o, "vp2rev-ins5p", rc(ins_after(15, $ins))); close $o;
# strand: CDS = start codon + random sense codons with sense codons 81..140 replaced by the
# reverse complement of the real codons 81..140, + stop codon
my $sc = substr($cds,0,3) . rnd(79) . rc(substr($cds,240,180)) . rnd(72) . substr($cds,-3);
die "len" if length($sc) != length($cds);
open($o, ">../noro.vp2rev.pvcoords.3.fa"); wfa($o, "vp2rev-strand", rc(substr($fwd,0,$cds_s-1) . $sc . substr($fwd,$cds_e))); close $o;
# positive strand counterparts of the indel test sequences, mutated in the full
# NC_001959 genome, for the existing NC_001959-vp2only model (CDS 6950..7588:+)
my $g_cds_s = 6950;
sub g_ins_after { my ($k,$s)=@_; my $p=$g_cds_s-1+$k; return substr($g,0,$p).$s.substr($g,$p); } # insert after CDS nt k
sub g_del_at    { my ($k,$n)=@_; my $p=$g_cds_s-1+$k; return substr($g,0,$p).substr($g,$p+$n); } # delete n nt after CDS nt k
my %p;
$p{"vp2fwd-ins5p"} = g_ins_after(15,  $ins);
$p{"vp2fwd-ins3p"} = g_ins_after(450, $ins);
$p{"vp2fwd-insrow"} = g_ins_after(165, $ins); # insert spans two rows of the blastx alignment output
$p{"vp2fwd-del"}   = g_del_at(300, 36);
$p{"vp2fwd-del5p"} = g_del_at(15,  36);
open($o, ">../noro.vp2only.pvcoords.4.fa"); for my $n (sort keys %p) { wfa($o, $n, $p{$n}); } close $o;
