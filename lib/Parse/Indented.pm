package Parse::Indented;

use warnings;
use strict;
use XML::xmlapi;

=head1 NAME

Parse::Indented - Given a Pythonesque set of indented lines, parses them into a convenient hierarchical structure

=head1 VERSION

Version 0.01

=cut

our $VERSION = '0.01';


=head1 SYNOPSIS

I have a bad habit of writing pseudocode when thinking of data structures.  Since I learned Python, it's only gotten worse.  So every time
I start a new research project, I end up scratching out some pseudocode specifications for the various data or semantics or what have you,
and then I bog down in writing yet another incomplete, buggy parser.  This module represents my first try at setting down that incomplete,
buggy parser where I can find it, so maybe next time I'll start from something other than scratch, and end up with a less incomplete and less
buggy parser.

Because I'm lazy, the output of this parser is an L<XML::xmlapi> structure, because that API is embedded in my brainstem at this point.

This parser does absolutely nothing with the actual lines themselves, but you can give it a function to call on each line to parse it and splice it
into the final result.  L<Parse::RecDescent::Simple> is a good choice (not that I'm partial or anything).

    use Parse::Indented;

    my $parser = Parse::Indented->new(sub {$_[0]});   # Just pass the line through as content for a simple parse.
    my $obj = $parser->parse (q{ });

=head1 SUBROUTINES/METHODS

=head2 new($line_parser)

Sets up a parser in advance with a line parser.

=cut

sub new {
   my ($class, $line_parser, $baseclass) = @_;
   $baseclass = "XML::xmlapi" unless $baseclass;
   bless { line_parser => $line_parser, baseclass => $baseclass}, $class;
}

=head2 parse ($text, $line_parser)

Call this with some indented text to parse.  If you set up a parser in advance, you don't need to pass a line parser; if you don't
want to mess with that, though, you can call this as a class method and give it the line parser on the spot.

C<Parse::Indented> ignores blank lines and any comments from # to the end of the line.  It trims leading and trailing space before asking
the line parser to parse the line for it.  The line parser is passed a string and is expected to return an L<XML::xmlapi> (or $baseclass) structure; if
it doesn't (that is, if it returns the same string you gave it, or a different string) C<Parse::Indented> will turn it into a <line> tag
with the text of the line in a "text" attribute, e.g. <line text="this is the line you passed"/>.

Children of each line are appended prettily to the parsed tag.  If the parsed tag already has some structure, that means you will need to be
a little careful with your semantics to avoid confusion.  Wise choices are left to the user; C<Parse::Indented> will gladly shoot you in the
foot if you tell it to.

If the line ends in a curly bracket {, everything until the next appropriately un-indented close curly bracket } will be sucked into a body element
attached to the line that started the curly bracket.

The line parser can return a list of the parsed line structure plus a flag "wants_sublines".  If that flag is set, then all indented lines under the
current line until the next un-indented line will be considered bracketed, and placed into the body of the line that started that mode.

For example:

   code something {
      indented code
      here
   }
   
This will create a line structure for "code something", with a body element under it containing "indented code\nhere\n".  I<Note>, however, that the
initial indentations for the indented code will be removed, as it's assumed you want the code to be unindented.

Similarly, if the line parser reports that the structure for "code something" wants sublines, this would be equivalent:

   code something
      indented code
      here
      
   more stuff later
   
See?  That would return line structures for "code something" and "more stuff later", with the same body for "code something" as in the previous example.
This is here for two reasons: first, my goal in this is to be able to type as few keystrokes as possible to express myself.  Second, this allows code
to look like the rest of the structure.  Esthetically, that's important to me.

=cut

sub parse {
   my ($self, $input, $line_parser, $root) = @_;
   
   if (not defined $line_parser) {
      eval { $line_parser = $self->{line_parser}; };   # This is in case we're called as a class method but without a line_parser.
   }
   if (not defined $line_parser) {
      $line_parser = sub {
         my $ret = $self->{baseclass}->create ("line");
         $ret->set ('text', $_[0]);
         return $ret;
      }
   }

   my $returns = $root || $self->{baseclass}->create('root');
   my $cursor = { o => {tag => $returns, parent=>$returns}, n => -1 };
   my $indent = -1;
   my @levels = ();
   my $bracket_parent = undef;
   my $bracket = 0;
   my $bracket_free = 0;
   my $bracket_text = '';
   my $bracket_indent = 0;
   
   for my $line (split /\n/, $input) {
	  
      my $this_indent;
	  
      if ($bracket) {  # We're in a multiline mode, so everything gets swept in.
         my ($one, $two);
	     if ($line =~ /^(\s+)(.*)$/) {
		    ($one, $two) = ($1, $2);
         } elsif ($line =~ /^}/ || $bracket_free) {
            ($one, $two) = ('', $line);
         } elsif ($line eq '') {
            ($one, $two) = (' ' x $bracket_indent, '');
         } else {
            warn "Confusing indentation.\n"; # TODO: error handling;
            return $returns;
         }
	     
         my $still_going = 1;
		 $this_indent = length($one); 
	     if ($bracket_indent == 0) {
		    $bracket_indent = $this_indent;
			$bracket_text = '';
		 }
		 if ($this_indent < $bracket_indent) {
		    if ($two =~ /^}/ and not $bracket_free) {
			   $bracket = 0; # Closing bracket.
			   my $bracket_body = $self->{baseclass}->create ("body");
			   $bracket_body->append ($self->{baseclass}->createtext ($bracket_text));
			   $bracket_parent->append_pretty($bracket_body);
			   next;
			} elsif (not $bracket_free) {
			   #print "Back-indented without closing bracket.\n";
			   return $returns; #TODO: error handling
			} else {
   			   $bracket = 0; # End of body.
			   my $bracket_body = $self->{baseclass}->create ("body");
			   $bracket_body->append ($self->{baseclass}->createtext ($bracket_text));
			   $bracket_parent->append_pretty($bracket_body);

               $still_going = 0;
            }
		 }
         if ($still_going) {
   	        $bracket_text .= substr($line, $bracket_indent) . "\n";
	        next;
         }
	  }

      $line =~ s/#.*$//;      # Add comments like this.
      $line =~ s/\s*$//;      # Discard all trailing space.
      next if $line eq '';    # Skip blank lines (after removal of comments and trailing space).
	  
	  my $colon = 0;          # Keep track of colon (we might want it later; currently not used).
	  if ($line =~ /:$/) {
	     $colon = 1;
		 $line =~ s/\s*:$//;
      }
	  
      if ($line =~ /^(\s+)(.*)$/) {     # Determine indentation of this line.
         $this_indent = length($1);
         $line = $2;
      } else {
         $this_indent = 0;
      }
	  
	  if ($line =~ /{$/) {
	     $bracket = 1;
		 $bracket_indent = 0;
         $bracket_free = 0;
		 $line =~ s/\s*{$//;
      }
      
      my ($new_tag, $wants_sublines) = &$line_parser ($line);
      if ($wants_sublines) {
         $bracket = 1;
         $bracket_indent = 0;
         $bracket_free = 1;
      }
	  $bracket_parent = $new_tag if $bracket == 1;

      if ($this_indent > $indent) {
         # Greater indentation means subobject
         push @levels, $cursor;

         my $new_line = { tag => $new_tag, parent => $$cursor{o} };
         $$new_line{parent}{tag}->append_pretty ($new_tag);
         $cursor = { o => $new_line, n => $this_indent };
      } else {
         if ($this_indent < $indent) {
            # Lesser indentation pops stack until "n" < $this_index
            do {
               $cursor = pop @levels;
            } until $$cursor{n} <= $this_indent;
         }
         # Equal indentation concats to current return list
         my $new_line = { tag => $new_tag, parent => $$cursor{o}{parent} };
         $$new_line{parent}{tag}->append_pretty ($new_tag);
         $cursor = { o => $new_line, n => $this_indent };
      }
      $indent = $this_indent;
   }
   
   return $returns;
}

=head1 AUTHOR

Michael Roberts, C<< <michael at vivtek.com> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-parse-indented at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Parse-Indented>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.




=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Parse::Indented


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Parse-Indented>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Parse-Indented>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/Parse-Indented>

=item * Search CPAN

L<http://search.cpan.org/dist/Parse-Indented/>

=back


=head1 ACKNOWLEDGEMENTS


=head1 LICENSE AND COPYRIGHT

Copyright 2010 Michael Roberts.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.


=cut

1; # End of Parse::Indented
