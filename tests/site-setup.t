#!/usr/bin/perl -w -I..
#
#  Test that the various feed output files exists.
#  (Run 'make feeds' if they do not)
#
# $Id: site-setup.t,v 1.7 2006-07-02 00:27:25 steve Exp $
#

use Test::More qw( no_plan );

#
#  We use "Test::File" if available.
#
BEGIN { use_ok( 'Test::File' ); }
require_ok( 'Test::File' );


file_exists_ok( "articles.rdf", "Articles RDF exists " );
file_writeable_ok( "articles.rdf", "Articles RDF writable " );


file_exists_ok( "headlines.rdf", "Headlines RDF exists " );
file_writeable_ok( "headlines.rdf", "Headlines RDF writable " );


file_exists_ok( "atom.xml", "Atom XML exists " );
file_writeable_ok( "atom.xml", "Atom XML writable " );


ok( -d "images/auth", "CAPTCHA directory exists" );
ok( -w "images/auth", "CAPTCHA directory writable" );
