#!/usr/bin/env perl
use Mojolicious::Lite;
use Bugzilla::Constants;
use Bugzilla::CGI::Mojo;
use Try::Tiny;

plugin 'PODRenderer';


app->hook(
    around_dispatch => sub {
        my ($next, $c) = @_;
        try {
            local %{ Bugzilla->request_cache } = ();
            Bugzilla->usage_mode(USAGE_MODE_MOJO);
            Bugzilla->cgi( Bugzilla::CGI::Mojo->new(controller => $c) );
            $next->();
        } catch {
            die $_ unless /\bModPerl::Util::exit\b/;
        };
    }
);

get '/' => sub {
    my $c = shift;
    my $user = Bugzilla->login(LOGIN_OPTIONAL);
    $c->render( template => 'index', user => $user );
};

app->start;
__DATA__

@@ index.html.ep
% layout 'default';
% title 'Welcome';

<p>Hello, <%= $user->name %> &lt;<%= $user->email %>&gt;
</p>

@@ layouts/default.html.ep
<!DOCTYPE html>
<html>
  <head><title><%= title %></title></head>
  <body><%= content %></body>
</html>
