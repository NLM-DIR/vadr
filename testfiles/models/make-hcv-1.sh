# Builds the hcv.1 test model (HCV genotype 2 RefSeq NC_009823) from a
# vadr-models-flavi directory ($VADRMODELDIR) whose HCV mat_peptides have
# CDS parents (1.7-3 or later; in 1.7-1 and 1.7-2 their parent is the gene).
rm -f hcv.1.cm* hcv.1.minfo
for a in NC_009823; do
    cp $VADRMODELDIR/$a.vadr.protein.fa* .
    $VADRINFERNALDIR/cmfetch $VADRMODELDIR/flavi.cm $a >> hcv.1.cm
    grep "^MODEL $a \|^FEATURE $a " $VADRMODELDIR/flavi.minfo >> hcv.1.minfo
done
$VADRINFERNALDIR/cmpress hcv.1.cm
