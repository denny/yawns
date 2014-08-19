#!/usr/bin/perl -w -I../lib/ # -*- cperl -*- #

=head1 NAME

Pages.pl  - Page generator code for Yawns

=cut

=head1 DESCRIPTION

  The various subroutines in this file are used to generate the actual
 page outputs.

  Control reaches here via a dispatch table in one of the front-ends,
 ajax.cgi, feeds.cgi, or index.cgi.

=cut

=head1 AUTHOR

 (c) 2001-2004 Denny De La Haye <denny@contentmanaged.org>
 (c) 2004-2006 Steve Kemp <steve@steve.org.uk>

 Steve
 --
 http://www.steve.org.uk/

 $Id: Pages.pl,v 1.649 2007-11-03 15:55:20 steve Exp $

=cut

#
#  Standard modules which we require.
use strict;
use warnings;


# standard perl modules
use Digest::MD5 qw(md5_base64 md5_hex);
use HTML::Entities;
use HTML::Template;    # Template library for webpage generation
use Mail::Verify;      # Validate Email addresses.
use Text::Diff;

use HTML::Linkize;
use Yawns::Adverts;
use Yawns::Article;
use Yawns::Comment::Notifier;
use Yawns::Date;
use Yawns::Formatters;
use Yawns::Preferences;
use Yawns::Submissions;
use Yawns::User;


=begin doc

Send an alert message

=end doc

=cut

sub send_alert    #
{
    my ($text) = (@_);

    #
    #  Abort if we're disabled, or have empty text.
    #
    my $enabled = conf::SiteConfig::get_conf('alerts') || 0;
    return unless ($enabled);
    return unless ( $text && length($text) );

    #
    #  Send it.
    #
    my $event = Yawns::Event->new();
    $event->send($text);
}



=begin doc

  A filter to allow dynamic page inclusions.

=end doc

=cut

sub mk_include_filter    #
{
    my $page = shift;
    return sub {
        my $text_ref = shift;
        $$text_ref =~ s/###/$page/g;
    };
}


=begin doc

  Load a layout and a page snippet with it.

=end doc

=cut

sub load_layout    #
{
    my ( $page, %options ) = (@_);

    #
    #  Make sure the snippet exists.
    #
    if ( -e "../templates/pages/$page" )
    {
        $page = "../templates/pages/$page";
    }
    else
    {
        die "Page not found: $page";
    }

    #
    #  Load our layout.
    #
    #
    #  TODO: Parametize:
    #
    my $layout = "../templates/layouts/default.template";
    my $l = HTML::Template->new( filename => $layout,
                                 %options,
                                 filter => mk_include_filter($page) );

    #
    #  IPv6 ?
    #
    if ( $ENV{ 'REMOTE_ADDR' } =~ /:/ )
    {
        $l->param( ipv6 => 1 ) unless ( $ENV{ 'REMOTE_ADDR' } =~ /^::ffff:/ );
    }

    #
    #  If we're supposed to setup a session token for a FORM element
    # then do so here.
    #
    my $setSession = 0;
    if ( $options{ 'session' } )
    {
        delete $options{ 'session' };
        $setSession = 1;
    }

    if ($setSession)
    {
        my $session = Singleton::Session->instance();
        $l->param( session => md5_hex( $session->id() ) );
    }

    #
    # Make sure the sidebar text is setup.
    #
    my $sidebar = Yawns::Sidebar->new();
    $l->param( sidebar_text   => $sidebar->getMenu() );
    $l->param( login_box_text => $sidebar->getLoginBox() );
    $l->param( site_title     => get_conf('site_title') );
    $l->param( metadata       => get_conf('metadata') );

    my $logged_in = 1;

    my $session  = Singleton::Session->instance();
    my $username = $session->param("logged_in");
    if ( $username =~ /^anonymous$/i )
    {
        $logged_in = 0;
    }
    $l->param( logged_in => $logged_in );

    return ($l);
}



# ===========================================================================
# CSRF protection.
# ===========================================================================
sub validateSession    #
{
    my $session = Singleton::Session->instance();

    #
    #  We cannot validate a session if we have no cookie.
    #
    my $username = $session->param("logged_in") || "Anonymous";
    return if ( !defined($username) || ( $username =~ /^anonymous$/i ) );

    my $form = Singleton::CGI->instance();

    # This is the session token we're expecting.
    my $wanted = md5_hex( $session->id() );

    # The session token we recieved.
    my $got = $form->param("session");

    if ( ( !defined($got) ) || ( $got ne $wanted ) )
    {
        permission_denied( invalid_session => 1 );

        # Close session.
        $session->close();

        # close database handle.
        my $db = Singleton::DBI->instance();
        $db->disconnect();
        exit;

    }
}




# ===========================================================================
# front page
# ===========================================================================

#
##
#
#  This function is a mess.
#
#  It must allow the user to step through the articles on the front-page
# either by section, or just globally.
#
##
#
sub front_page    #
{

    #
    #  Gain access to the objects we use.
    #
    my $form     = Singleton::CGI->instance();
    my $session  = Singleton::Session->instance();
    my $username = $session->param("logged_in");


    #
    # Gain access to the articles
    #
    my $articles = Yawns::Articles->new();

    #
    # Get the last article number.
    #
    my $last = $articles->count();
    $last += 1;

    #
    # How many do we show on the front page?
    #
    my $count = get_conf('headlines');

    #
    # Get the starting (maximum) number of the articles to view.
    #
    my $start = $last;
    $start = $form->param('start') if $form->param('start');
    if ( $start =~ /([0-9]+)/ )
    {
        $start = $1;
    }

    $start = $last if ( $start > $last );

    #
    # get required articles from database
    #
    my ( $the_articles, $last_id ) = $articles->getArticles( $start, $count );

    $last_id = 0 unless $last_id;


    #
    # Data for pagination
    #
    my $shownext  = 0;
    my $nextfrom  = 0;
    my $nextcount = 0;

    my $showprev  = 0;
    my $prevfrom  = 0;
    my $prevcount = 0;


    $nextfrom = $start + 10;
    if ( $nextfrom > $last ) {$nextfrom = $last;}

    $nextcount = 10;
    if ( $nextfrom + 10 > $last ) {$nextcount = $last - $start;}
    while ( $nextcount > 10 )
    {
        $nextcount -= 10;
    }

    $prevfrom = $last_id - 1;
    if ( $prevfrom < 0 ) {$prevfrom = 0;}

    $prevcount = 10;
    if ( $prevfrom - 10 < 0 ) {$prevcount = $start - 11;}

    if ( $start < $last )
    {
        $shownext = 1;
    }
    if ( $start > 10 )
    {
        $showprev = 1;
    }

    # read in the template file
    my $template = load_layout( "index.inc", loop_context_vars => 1 );


    # fill in all the parameters we got from the database
    if ($last_id)
    {
        $template->param( articles => $the_articles );
    }


    $template->param( shownext  => $shownext,
                      nextfrom  => $nextfrom,
                      nextcount => $nextcount,
                      showprev  => $showprev,
                      prevfrom  => $prevfrom,
                      prevcount => $prevcount,
                      content   => $last_id,
                    );

    #
    #  Add in the tips
    #
    my $weblogs     = Yawns::Weblogs->new();
    my $recent_tips = $weblogs->getTipEntries();
    $template->param( recent_tips => $recent_tips ) if ($recent_tips);


    # generate the output
    print $template->output;
}


# ===========================================================================
# Submit article
# ===========================================================================

sub submit_article
{

    #
    # Gain access to objects we use.
    #
    my $form     = Singleton::CGI->instance();
    my $session  = Singleton::Session->instance();
    my $username = $session->param("logged_in");


    # get new/preview status for article submissions
    my $submit = '';
    $submit = $form->param('submit') if defined $form->param('submit');

    # set some variables
    my $anon    = 0;
    my $new     = 0;
    my $preview = 0;
    my $confirm = 0;
    $anon = 1 if ( $username =~ /^anonymous$/i );
    $new     = 1 if $submit eq 'new';
    $preview = 1 if $submit eq 'Preview';
    $confirm = 1 if $submit eq 'Confirm';

    my $submit_title  = '';
    my $preview_title = '';
    my $submit_body   = '';
    my $preview_body  = '';

    my $submit_ondate = '';
    my $submit_attime = '';
    my $submission_id = 0;    # ID of the article which has been submitted.


    #
    #  Anonymous users can't post articles
    #
    if ( $username =~ /^anonymous$/i )
    {
        return ( permission_denied( login_required => 1 ) );
    }


    if ($preview)
    {

        # validate session
        validateSession();

        $submit_title = $form->param('submit_title') || " ";
        $submit_body  = $form->param('submit_body')  || " ";

        # HTML Encode the title.
        $submit_title  = HTML::Entities::encode_entities($submit_title);
        $preview_title = $submit_title;

        #
        #  Create the correct formatter object.
        #
        my $creator = Yawns::Formatters->new();
        my $formatter = $creator->create( $form->param('type'), $submit_body );



        #
        #  Get the formatted and safe versions.
        #
        $preview_body = $formatter->getPreview();
        $submit_body  = $formatter->getOriginal();


        #
        # Linkize the preview.
        #
        my $linker = HTML::Linkize->new();
        $preview_body = $linker->linkize($preview_body);


        # get date in human readable format
        ( $submit_ondate, $submit_attime ) = Yawns::Date::get_str_date();

    }
    elsif ($confirm)
    {

        # validate session
        validateSession();

        #
        #  Get the data.
        #
        $submit_title = $form->param('submit_title') || " ";
        $submit_body  = $form->param('submit_body')  || " ";

        # HTML Encode the title.
        $submit_title = HTML::Entities::encode_entities($submit_title);

        {
            my $home_url = get_conf('home_url');
            my $home     = $home_url . "/users/$username";
            send_alert(
                "Article submitted by <a href=\"$home\">$username</a> - $submit_title"
            );
        }

        #
        #  Create the correct formatter object.
        #
        my $creator = Yawns::Formatters->new();
        my $formatter = $creator->create( $form->param('type'), $submit_body );

        #
        #  Get the submitted body.
        #
        $submit_body = $formatter->getPreview();

        #
        # Linkize the preview.
        #
        my $linker = HTML::Linkize->new();
        $submit_body = $linker->linkize($submit_body);

        my $submissions = Yawns::Submissions->new();
        $submission_id =
          $submissions->addArticle( title    => $submit_title,
                                    bodytext => $submit_body,
                                    ip       => $ENV{ 'REMOTE_ADDR' },
                                    author   => $username
                                  );
    }

    # open the html template
    my $template = load_layout( "submit_article.inc", session => 1 );

    # fill in all the parameters you got from the database
    $template->param( anon          => $anon,
                      new           => $new,
                      preview       => $preview,
                      confirm       => $confirm,
                      username      => $username,
                      submit_title  => $submit_title,
                      submit_body   => $submit_body,
                      preview_title => $preview_title,
                      preview_body  => $preview_body,
                      submit_ondate => $submit_ondate,
                      submit_attime => $submit_attime,
                      submission_id => $submission_id,
                      title         => "Submit Article",
                      tag_url => "/ajax/addtag/submission/$submission_id/",
                    );


    #
    #  Make sure the format is setup.
    #
    if ( $form->param('type') )
    {
        $template->param( $form->param('type') . "_selected" => 1 );
    }
    else
    {

        #
        #  Choose the users format.
        #
        my $prefs = Yawns::Preferences->new( username => $username );
        my $type = $prefs->getPreference("posting_format") || "text";

        $template->param( $type . "_selected" => 1 );
    }


    # generate the output
    print $template->output;
}




# ===========================================================================
# submit comment
#
#   This could either be on a poll, an article, or a weblog entry.
#
# ===========================================================================

sub submit_comment
{

    #
    #  Gain access to the objects we use.
    #
    my $db        = Singleton::DBI->instance();
    my $form      = Singleton::CGI->instance();
    my $session   = Singleton::Session->instance();
    my $username  = $session->param("logged_in");
    my $anonymous = 0;

    #  Anonymous user?
    $anonymous = 1 if ( $username =~ /^anonymous$/i );

    #
    #  Is the user non-anonymous?
    #
    if ( !$anonymous )
    {

        #
        #  Is the user suspended?
        #
        my $user = Yawns::User->new( username => $username );
        my $userdata = $user->get();

        if ( $userdata->{ 'suspended' } )
        {
            return ( permission_denied( suspended => 1 ) );
        }
    }


    # get new/preview status for comment submissions
    my $comment   = '';
    my $onarticle = undef;
    my $onpoll    = undef;
    my $onweblog  = undef;
    my $oncomment = undef;

    #
    # The comment which is being replied to.
    #
    $comment = $form->param('comment') if defined $form->param('comment');

    #
    #  Article we're commenting on - could be blank for poll comments.
    #
    $onarticle = $form->param('onarticle') if defined $form->param('onarticle');

    #
    #  Poll ID we're commenting on - could be blank for article comments
    #
    $onpoll = $form->param('onpoll') if defined $form->param('onpoll');

    #
    #  Weblog ID we're commenting on.
    #
    $onweblog = $form->param('onweblog') if defined $form->param('onweblog');

    #
    #  Comment we're replying to.
    #
    $oncomment = $form->param('oncomment') if defined $form->param('oncomment');

    # set some variables
    my $new     = 0;
    my $preview = 0;
    my $confirm = 0;
    $new     = 1 if $comment eq 'new';
    $confirm = 1 if $comment eq 'Confirm';
    $preview = 1 if $comment eq 'Preview';


    #
    #  If a user posts a comment we store the time in their
    # session object.
    #
    #  Later comments use this time to test to see if they should
    # slow down.
    #
    my $seconds = $session->param("last_comment_time");
    if ( defined($seconds) &&
         ( ( time() - $seconds ) < 60 ) )
    {

        #
        #  If the comment poster is a privileged user then
        # we'll be allowed to post two comments in sixty seconds,
        # otherwise they'll receive an error.
        #
        my $perms = Yawns::Permissions->new( username => $username );
        if ( !$perms->check( priv => "fast_comments" ) )
        {

            #
            #  Denied.
            #
            return ( permission_denied( too_fast => 1 ) );
        }
    }


    #
    # The data that the user is adding to the page.
    #
    my $submit_title = '';
    my $submit_body  = '';
    my $preview_body = '';


    #
    #  When replying to a comment:
    #
    my $parent_subject = '';
    my $parent_body    = '';
    my $parent_author  = '';
    my $parent_ondate  = '';
    my $parent_ontime  = '';
    my $parent_ip      = '';


    #
    #  Weblog link to manage gid translation
    #
    my $weblog_link = '';

    #
    #  The comment title
    #
    my $title = '';
    if ($onarticle)
    {
        my $art = Yawns::Article->new( id => $onarticle );
        $title = $art->getTitle();
    }
    elsif ($onpoll)
    {
        my $poll = Yawns::Poll->new( id => $onpoll );
        $title = $poll->getTitle();
    }
    elsif ($onweblog)
    {
        my $weblog = Yawns::Weblog->new( gid => $onweblog );
        my $owner  = $weblog->getOwner();
        my $id     = $weblog->getID();
        $title       = $weblog->getTitle();
        $weblog_link = "/users/$owner/weblog/$id";
    }



    #
    #  If we're replying to a comment we want to show the parent
    # comment - so we need to fetch that information.
    #
    if ($oncomment)
    {

        #
        # TODO: Optimize!
        #
        my $comment =
          Yawns::Comment->new( article => $onarticle,
                               poll    => $onpoll,
                               weblog  => $onweblog,
                               id      => $oncomment
                             );
        my $commentStuff = $comment->get();


        $parent_ip      = $commentStuff->{ 'ip' };
        $parent_subject = $commentStuff->{ 'title' };
        $parent_body    = $commentStuff->{ 'body' };
        $parent_author  = $commentStuff->{ 'author' };
        $parent_ontime  = $commentStuff->{ 'time' };
        $parent_ondate  = $commentStuff->{ 'date' };
    }

    #
    #  Get the date and time
    #
    my $submit_ondate = '';
    my $submit_attime = '';

    #
    # Get the date and time
    #
    ( $submit_ondate, $submit_attime ) = Yawns::Date::get_str_date();

    #
    #  And IP address
    #
    my $ip = $ENV{ 'REMOTE_ADDR' };
    if ( defined($ip) && length($ip) )
    {
        if ( $ip =~ /([0-9]+)\.([0-9]+)\.([0-9]+)\.([0-9]+)/ )
        {
            $ip = $1 . "." . $2 . ".xx.xx";
        }
        if ( $ip =~ /^([^:]+):/ )
        {
            $ip = $1 . ":0xx:0xx:0xxx:0xxx:0xxx:xx";
        }
    }


    #
    # Previewing the comment
    #
    if ($preview)
    {

        # validate session
        validateSession();

        $submit_title = $form->param('submit_title') || "";
        $submit_body  = $form->param('submit_body')  || "";

        # HTML Encode the title.
        $submit_title = HTML::Entities::encode_entities($submit_title);

        #
        #  Create the correct formatter object.
        #
        my $creator = Yawns::Formatters->new();
        my $formatter = $creator->create( $form->param('type'), $submit_body );


        #
        #  Get the formatted and safe versions.
        #
        $preview_body = $formatter->getPreview();
        $submit_body  = $formatter->getOriginal();

        #
        # Linkize the preview.
        #
        my $linker = HTML::Linkize->new();
        $preview_body = $linker->linkize($preview_body);


    }
    elsif ($confirm)
    {

        # validate session
        validateSession();

        #
        # We detect multiple identical comment posting via the
        # session too.
        #
        $submit_body = $form->param('submit_body');
        if ( defined($submit_body) && length($submit_body) )
        {
            my $hash = md5_base64( Encode::encode( "utf8", $submit_body ) );
            my $used = $session->param($hash);


            if ( defined($used) )
            {
                return ( permission_denied( duplicate_comment => 1 ) );
            }
            else
            {
                $session->param( $hash, "used" );
            }
        }


        #
        #  Get the data.
        #
        $submit_title = $form->param('submit_title') || "";
        $submit_body  = $form->param('submit_body')  || "";

        # HTML Encode the title.
        $submit_title = HTML::Entities::encode_entities($submit_title);

        #
        #  "Bad words" testing is *always* used.
        #
        my $stop = get_conf('stop_words');
        if ( defined($stop) && length($stop) )
        {

            #
            #  If the configuration file has a mentioned word
            # then drop the we match.
            #
            foreach my $bad ( split( /,/, $stop ) )
            {
                if ( $submit_body =~ /$bad/i )
                {
                    return (
                             permission_denied( bad_words => 1,
                                                stop_word => $bad
                                              ) );
                }
            }
        }

        #
        #  If anonymous we use Steve's RPC server to test comment
        # validity.
        #
        if ( ($anonymous) &&
             ( get_conf("rpc_comment_test") ) )
        {

            my %params;
            $params{ 'comment' } = $submit_body;
            $params{ 'ip' }      = $ENV{ 'REMOTE_ADDR' };
            $params{ 'subject' } = $submit_title;

            #
            #  Build up a link to the website we're on.
            #
            my $protocol = "http://";
            if ( defined( $ENV{ 'HTTPS' } ) && ( $ENV{ 'HTTPS' } =~ /on/i ) )
            {
                $protocol = "https://";
            }
            $params{ 'site' } = $protocol . $ENV{ "SERVER_NAME" };

            #
            #  If the module(s) aren't available, or talking to the
            # server fails then we'll allow the comment.
            #
            #  That is clearly the correct thing to do.
            #
            my $drop = 0;
            eval {
                require RPC::XML;
                require RPC::XML::Client;

                #
                #  Host:port to test against
                #
                my $host = get_conf("rpc_comment_host");
                my $port = get_conf("rpc_comment_port");

                #
                #  Special options to use, if any.
                #
                my $opts = get_conf("rpc_test_options");
                if ($opts)
                {
                    $params{ 'options' } = $opts;
                }

                my $client = RPC::XML::Client->new("http://$host:$port");
                my $req    = RPC::XML::request->new( 'testComment', \%params );
                my $res    = $client->send_request($req);
                my $result = $res->value();

                if ( $result =~ /^spam/i )
                {
                    $drop = 1;
                }
            };

            if ($drop)
            {
                return ( permission_denied( blogspam => 1 ) );
            }
        }


        #
        #  Create the correct formatter object.
        #
        my $creator = Yawns::Formatters->new();
        my $formatter = $creator->create( $form->param('type'), $submit_body );

        #
        #  Get the submitted body.
        #
        $submit_body = $formatter->getPreview();

        #
        # Linkize the preview.
        #
        my $linker = HTML::Linkize->new();
        $submit_body = $linker->linkize($submit_body);

        #
        #  If we're anonymous
        #
        if ($anonymous)
        {
            if ( $submit_body =~ /http:\/\// )
            {

                #
                #  ANonymous users cannot post links
                #
                return ( permission_denied( anonylink => 1 ) );
            }
        }

        #
        #  Actually add the comment.
        #
        my $comment = Yawns::Comment->new();
        my $num = $comment->add( article   => $onarticle,
                                 poll      => $onpoll,
                                 weblog    => $onweblog,
                                 oncomment => $oncomment,
                                 title     => $submit_title,
                                 username  => $username,
                                 body      => $submit_body,
                               );



        {
            my $llink = get_conf('home_url');
            if ($onarticle)
            {
                $llink .= "/articles/" . $onarticle . "#comment_" . $num;
            }
            if ($onpoll)
            {
                $llink .= "/polls/" . $onpoll . "#comment_" . $num;
            }
            if ($onweblog)
            {
                my $weblog = Yawns::Weblog->new( gid => $onweblog );
                my $owner  = $weblog->getOwner();
                my $id     = $weblog->getID();
                $llink .= "/users/$owner/weblog/$id" . "#comment_" . $num;
            }

            send_alert(
                    "New comment posted <a href=\"$llink\">$submit_title</a>.");
        }


        #
        #  Now handle the notification sending
        #
        my $notifier =
          Yawns::Comment::Notifier->new( onarticle => $onarticle,
                                         onpoll    => $onpoll,
                                         onweblog  => $onweblog,
                                         oncomment => $oncomment
                                       );

        #
        #  This will not do anything if the notifications are disabled
        # by the article author, comment poster, etc.
        #
        $notifier->sendNotification($num);

        #
        # Save the comment time.
        #
        $session->param( "last_comment_time", time() );

        #
        # Save the MD5 hash of the last comment posted.
        #
        $session->param( md5_base64( Encode::encode( "utf8", $submit_body ) ),
                         1 );



    }
    elsif ($new)
    {
        if ($oncomment)
        {
            my $comment =
              Yawns::Comment->new( article => $onarticle,
                                   poll    => $onpoll,
                                   weblog  => $onweblog,
                                   id      => $oncomment
                                 );
            my $commentStuff = $comment->get();

            $submit_title = $commentStuff->{ 'title' };


            if ( $submit_title =~ /^Re:/ )
            {

                # Comment starts with 'Re:' already.
            }
            else
            {
                $submit_title = 'Re: ' . $submit_title;
            }
        }
        else
        {

            #
            # Get title of article being replied to
            #
            if ($onarticle)
            {
                my $art = Yawns::Article->new( id => $onarticle );
                $submit_title = $art->getTitle();
                $submit_title = 'Re: ' . $submit_title;
            }

            #
            # Get poll question of poll being replied to.
            #
            if ($onpoll)
            {
                my $poll = Yawns::Poll->new( id => $onpoll );
                $submit_title = 'Re: ' . $poll->getTitle();
            }

            #
            # Get weblog title of entry
            #
            if ($onweblog)
            {
                my $weblog = Yawns::Weblog->new( gid => $onweblog );
                $submit_title = 'Re: ' . $weblog->getTitle();
            }
        }

        #
        #  Get the users signature.
        #
        my $u = Yawns::User->new( username => $username );
        my $userdata = $u->get();
        $submit_body = $userdata->{ 'sig' };
    }

    # open the html template
    my $template = load_layout( "submit_comment.inc", session => 1 );

    # fill in all the parameters you got from the database
    $template->param( anon           => $anonymous,
                      new            => $new,
                      confirm        => $confirm,
                      preview        => $preview,
                      username       => $username,
                      onarticle      => $onarticle,
                      oncomment      => $oncomment,
                      onpoll         => $onpoll,
                      onweblog       => $onweblog,
                      weblog_link    => $weblog_link,
                      submit_title   => $submit_title,
                      submit_body    => $submit_body,
                      submit_attime  => $submit_attime,
                      submit_ondate  => $submit_ondate,
                      ip             => $ip,
                      parent_body    => $parent_body,
                      parent_subject => $parent_subject,
                      parent_author  => $parent_author,
                      parent_date    => $parent_ondate,
                      parent_time    => $parent_ontime,
                      parent_ip      => $parent_ip,
                      title          => $title,
                      preview_body   => $preview_body,
                    );

    #
    #  Make sure the format is setup.
    #
    if ( $form->param('type') )
    {
        $template->param( $form->param('type') . "_selected" => 1 );
    }
    else
    {

        #
        #  Choose the users format.
        #
        my $prefs = Yawns::Preferences->new( username => $username );
        my $type = $prefs->getPreference("posting_format") || "text";

        $template->param( $type . "_selected" => 1 );
    }


    # generate the output
    print $template->output;

}




# ===========================================================================
# create a new user account.
# ===========================================================================
sub new_user
{

    # Get access to the form.
    my $form = Singleton::CGI->instance();

    #
    #  Get the currently logged in user.
    #
    my $session  = Singleton::Session->instance();
    my $username = $session->param("logged_in");

    # Deny access if the user is already logged in.
    if ( $username !~ /^anonymous$/i )
    {
        return ( permission_denied( already_logged_in => 1 ) );
    }


    my $new_user_name  = '';
    my $new_user_email = '';

    my $new_user_sent  = 0;
    my $already_exists = 0;

    my $blank_email   = 0;
    my $invalid_email = 0;

    my $blank_username   = 0;
    my $invalid_username = 0;
    my $prev_banned      = 0;
    my $prev_email       = 0;
    my $invalid_hash     = 0;
    my $mail_error       = "";


    if ( $form->param('new_user') eq 'Create User' )
    {

        # validate session
        validateSession();

        $new_user_name = $form->param('new_user_name');
        $new_user_name =~ s/&/\+/g;
        $new_user_email = $form->param('new_user_email');

        if ( $new_user_name =~ /^([0-9a-zA-Z_-]+)$/ )
        {

            #
            # Usernames are 1-25 characters long.
            #
            if ( length($new_user_name) > 25 )
            {
                $invalid_username = 1;
            }

            #
            # Make sure we have an email address.
            #
            if ( !length($new_user_email) )
            {
                $blank_email = 1;
            }


            #
            #  See if this user comes from an IP address with a previous suspension.
            #
            my $db = Singleton::DBI->instance();
            my $sql = $db->prepare(
                "SELECT COUNT(username) FROM users WHERE ip=? AND suspended=1");
            $sql->execute( $ENV{ 'REMOTE_ADDR' } );
            $prev_banned = $sql->fetchrow_array();
            $sql->finish();


            $sql = $db->prepare(
                         "SELECT COUNT(username) FROM users WHERE realemail=?");
            $sql->execute($new_user_email);
            $prev_email = $sql->fetchrow_array();
            $sql->finish();

            if ($prev_banned)
            {
                send_alert( "Denied registration for '$new_user_name' from " .
                            $ENV{ 'REMOTE_ADDR' } );
            }
            if ($prev_banned)
            {
                send_alert(
                     "Denied registration for in-use email " . $new_user_email .
                       " " . $ENV{ 'REMOTE_ADDR' } );
            }

            #
            # Now test to see if the email address is valid
            #
            $invalid_email = Mail::Verify::CheckAddress($new_user_email);

            if ( $invalid_email == 1 )
            {
                $mail_error = "No email address was supplied.";
            }
            elsif ( $invalid_email == 2 )
            {
                $mail_error =
                  "There is a syntaxical error in the email address.";
            }
            elsif ( $invalid_email == 3 )
            {
                $mail_error =
                  "There are no DNS entries for the host in question (no MX records or A records).";
            }
            elsif ( $invalid_email == 4 )
            {
                $mail_error =
                  "There are no live SMTP servers accepting connections for this email address.";
            }

            #
            # Test to see if the username already exists.
            #
            if ( ( $invalid_email +
                   $prev_email +
                   $prev_banned +
                   $invalid_username +
                   $blank_email
                 ) < 1
               )
            {
                my $users = Yawns::Users->new();
                my $exists = $users->exists( username => $new_user_name );
                if ($exists)
                {
                    $already_exists = 1;
                }
                else
                {
                    my $password = '';
                    $password =
                      join( '', map {( 'a' .. 'z' )[rand 26]} 0 .. 7 );

                    my $ip = $ENV{ 'REMOTE_ADDR' };
                    if ( $ip =~ /^::ffff:(.*)/ )
                    {
                        $ip = $1;
                    }

                    my $user =
                      Yawns::User->new( username  => $new_user_name,
                                        email     => $new_user_email,
                                        password  => $password,
                                        ip        => $ip,
                                        send_mail => 1
                                      );
                    $user->create();

                    send_alert(
                        "New user, <a href=\"http://www.debian-administration.org/users/$new_user_name\">$new_user_name</a>, created from IP $ip."
                    );

                    $new_user_sent = 1;
                }
            }
        }
        else
        {
            if ( length($new_user_name) )
            {
                $invalid_username = 1;
            }
            else
            {
                $blank_username = 1;
            }
        }
    }


    # open the html template
    my $template = load_layout( "new_user.inc", session => 1 );

    # set the required values
    $template->param( new_user_sent    => $new_user_sent,
                      new_user_email   => $new_user_email,
                      already_exists   => $already_exists,
                      invalid_email    => $invalid_email,
                      mail_error       => $mail_error,
                      invalid_username => $invalid_username,
                      blank_email      => $blank_email,
                      blank_username   => $blank_username,
                      prev_banned      => $prev_banned,
                      prev_email       => $prev_email,
                      new_user_name    => $new_user_name,
                      new_user_email   => $new_user_email,
                      title            => "Register Account",
                    );

    # generate the output
    print $template->output;

}




# ===========================================================================
# Permission Denied - or other status message
# ===========================================================================
sub permission_denied    #
{
    my (%parameters) = (@_);

    # set up the HTML template
    my $template = load_layout("permission_denied.inc");

    # title
    my $title = $parameters{ 'title' } || "Permission Denied";
    $template->param( title => $title );

    #
    # If we got a custom option then set that up.
    #
    if ( scalar( keys(%parameters) ) )
    {
        $template->param(%parameters);
        $template->param( custom_error => 1 );
    }

    # generate the output
    print $template->output;
}


sub dump_details    #
{
    my $date = `date`;
    chomp($date);
    my $host = `hostname`;
    chomp($host);

    print "This request was received at $date on $host.\n\n";

    #
    #  Environment dump.
    #
    print "\n\n";
    print "Environment\n";
    foreach my $key ( sort keys %ENV )
    {
        print "$key\t\t\t$ENV{$key}\n";
    }

    print "\n\n";
    print "Submissions\n";
    my $form = Singleton::CGI->instance();

    foreach my $key ( $form->param() )
    {
        print $key . "\t\t\t" . $form->param($key);
        print "\n";
    }
}



1;



=head1 LICENSE

Copyright (c) 2005-2007 by Steve Kemp.  All rights reserved.

This module is free software;
you can redistribute it and/or modify it under
the same terms as Perl itself.
The LICENSE file contains the full text of the license.

=cut
