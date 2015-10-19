#!/usr/bin/perl

use strict;
use warnings;

use Text::ParseWords;


#Build a tree with all tracks
my $rH_trackTree = {};

my %subGroupDict;
my %metadataDict;
my @orderedSubGroups;
my @orderedmetadata;

my $file = $ARGV[0];



&main();
sub main {
   parseFile($file);
   buildDictionaries();
   printHeader();
   printLines();
}


sub parseFile {
   my $file = shift;
   
   open(trackDB, "<$file");
   
   my %currentStanza;
   my $lineCount = 0;
   while (my $line = <trackDB>) {
      chomp $line;
      $line =~ s/\s$//;     #Remove spaces at the end of lines
      $lineCount++;
      
      if ($line =~ /^\s*$/) {
         if (scalar(keys(%currentStanza)) > 0) {
            processTrack(\%currentStanza);
            undef %currentStanza;
         }
      }
      elsif ($line =~ /^\s*\#/) {         #Ignore commented lines
         next;
      }
      else {
         #Get first line number for new stanza
         if (!defined($currentStanza{'line_nb'})) {
            $currentStanza{'line_nb'} = $lineCount;
         }
         
         $line =~ /^\s*(\w+)\s(.*)$/;
         my $setting = $1;
         my $value = $2;
         $currentStanza{$1} = $2;
      }
   }
   
   close(trackDB);
}


sub processTrack {
   my $rH_stanza = shift;
   
   my $trackName = $rH_stanza->{'track'};
   my $parentTrack = getParentTrackName($rH_stanza);

   my %newHash = (%$rH_stanza, %{$rH_trackTree->{$trackName} || {}});
   $rH_trackTree->{$trackName} = $rH_stanza = \%newHash;
   
   if ($parentTrack) {
      $parentTrack =~ s/^([^\s]+)\s.*$/$1/;
      my $parentStanza = $rH_trackTree->{$parentTrack} || {track => $parentTrack};
      $parentStanza->{'child_stanza'} = $rH_stanza;
      
      $rH_stanza->{'parent_stanza'} = $parentStanza;
   }
}

sub getParentTrackName {
   my $rH_stanza = shift;
   my $parentTrackName = $rH_stanza->{'parent'} || $rH_stanza->{'superTrack'} || $rH_stanza->{'subTrack'};
   return $parentTrackName
}



sub buildDictionaries {
   foreach my $trackName (keys(%$rH_trackTree)) {
      my $rH_stanza = $rH_trackTree->{$trackName};
      
      #Fetch all keys from the "subGroups" setting, as they are not necessarily defined in parent track "subGroup1, subGroup2, etc."
      if (defined($rH_stanza->{"subGroups"})) {
         my @tokens = split(" ", $rH_stanza->{"subGroups"});
         foreach my $elem (@tokens) {
            $elem =~ /^([^=]+)=/;
            $subGroupDict{$1} = 1;
         }
      }
      
      #Metadata includes a fix for roadmap data which has metadata keys that include spaces
      if (defined($rH_stanza->{"metadata"})) {
         my $metadata = $rH_stanza->{"metadata"};
         my $rA_tokens = tokenizeMetadata($metadata);
         foreach my $elem (@$rA_tokens) {
            $elem =~ /^([^=]+)=/;
            $metadataDict{$1} = 1;
         }
      }
   }
   
   #Sort the dictionaries and assign a column number
   @orderedSubGroups = sort { $a cmp $b } keys(%subGroupDict);
   @orderedmetadata = sort { $a cmp $b } keys(%metadataDict);
   
   #Set the proper colum number in the dictionary
   my $i = 0;
   map { $subGroupDict{$_} = $i++; } @orderedSubGroups;
   $i = 0;
   map { $subGroupDict{$_} = $i++; } @orderedSubGroups;
}


sub printHeader {
   my @subGroupTokens = map { qq{"subgroup:$_"}} @orderedSubGroups;
   my @metadataTokens = map { $_ =~ s/"/""/g; qq{"metadata:$_"}} @orderedmetadata;
   
   print qq{"linecount","track_name","shortLabel","longLabel","Parent Group","Group","BigDataUrl",};
   print join(",", @subGroupTokens);
   print ",";
   print join(",", @metadataTokens);
   
   print "\n";
}


sub printLines {
   #Order stanzas by line number to print
   my @orderedTrackName = sort { $rH_trackTree->{$a}->{'line_nb'} <=> $rH_trackTree->{$b}->{'line_nb'} } keys(%$rH_trackTree);
   
   foreach my $trackName (@orderedTrackName) {
      my $rH_stanza = $rH_trackTree->{$trackName};
      
      #Print only "leaf" stanzas
      if (!defined($rH_stanza->{'child_stanza'})) {
         
         print "\"" . $rH_stanza->{'line_nb'} . "\",";
         print "\"" . $rH_stanza->{'track'} . "\",";
         print "\"" . $rH_stanza->{'shortLabel'} . "\",";
         print "\"" . $rH_stanza->{'longLabel'} . "\",";
         
         #If current track group is part of a super-group
         if ($rH_stanza->{'parent_stanza'}->{'parent_stanza'}) {
            print "\"" . $rH_stanza->{'parent_stanza'}->{'parent_stanza'}->{'track'} . "\",";
         }
         else {
            print ",";
         }
         
         #Track group
         print "\"" . $rH_stanza->{'parent_stanza'}->{'track'} . "\",";
         print "\"" . $rH_stanza->{'bigDataUrl'} . "\",";
         
         my %stanzaSubGroups;
         if (defined($rH_stanza->{'subGroups'})) {
            my @tokens = split(" ", $rH_stanza->{'subGroups'});
            foreach my $elem (@tokens) {
               $elem =~ /^([^=]+)=(.+)$/;
               my $type = $1;
               my $val = $2;
               $stanzaSubGroups{$type} = $val;
            }
         }
         my @subGroupTokens = map { defined($stanzaSubGroups{$_}) ? qq{"$stanzaSubGroups{$_}"} : "" } @orderedSubGroups;
         print (join(",", @subGroupTokens));

         my %stanzaMetadata;         
         if (defined($rH_stanza->{'metadata'})) {
            my $rA_tokens = tokenizeMetadata($rH_stanza->{'metadata'});
            foreach my $elem (@$rA_tokens) {
               $elem =~ /^([^=]+)=(.*)$/;
               my $type = $1;
               my $val = $2;
               
               #Remove enclosing double quotes if there are
               if ($val =~ /^"(.*)"$/) {
                   $val = $1;
               }
               
               $stanzaMetadata{$type} = $val;
            }
         }
         
         my @metadataTokens = map { defined($stanzaMetadata{$_}) ? qq{"$stanzaMetadata{$_}"} : "" } @orderedmetadata;
         print ",";
         print (join(",", @metadataTokens));
         
         #End of this stanza, next line in the output
         print "\n";
      }
   }
}


#Instead of just splitting on spaces not included in double quotes, we need to cover the Roadmap case where some keys have spaces (such as "sample alias"),
#and replace them with underscores
sub tokenizeMetadata {
   my $metadata = shift;
   
   $metadata =~ s/'/\\'/g;      #Escape apostrophes
   $metadata =~ s/\s+$//;       #Remove trailing spaces that will create undesired tokens
   
   my @words = quotewords('\s+', 1, $metadata);
   
   my @finalArray;
   for (my $i=0; $i<scalar(@words); $i++) {
      my $word = $words[$i];
      while (!($word =~ /=/)) {
         $word .= "_" . $words[++$i];
      }
      push(@finalArray, $word);
   }
   
   return \@finalArray;
}
