package RILFeed;
use strict;
use LWP::Simple;
use URI;
use XML::RSS;
use App::Cache;
use DateTime;
use DateTime::Format::Mail;
use Encode;
use WebService::Simple;

my $cache = App::Cache->new;
my $format = DateTime::Format::Mail->new;

my $apikey = $ENV{RIL_APIKEY};

my $ril = WebService::Simple->new(
    base_url => "https://readitlaterlist.com/v2/",
    param => { apikey => $apikey },
    response_parser => 'JSON',
);

sub app {
    my $class = shift;
    return sub { $class->run(@_) };
}

sub run {
    my($class, $env) = @_;

    my $res = eval {
        if ($env->{PATH_INFO} eq '/rss') {
            $class->serve_rss($env);
        } else {
            return [ 404, [ 'Content-Type', 'text/plain' ], [ 'Not Found' ] ];
        }
    };

    if ($@) {
        $res = [ 500, [ 'Content-Type', 'text/plain' ], [ "$@" ] ];
    }

    return $res;
}

sub serve_rss {
    my($class, $env) = @_;

    my $feed = XML::RSS->new(version => '2.0');
    $feed->channel(
        title => "My Reading List",
        link  => "http://readitlaterlist.com/users/$ENV{RIL_USERNAME}",
    );

    $feed->add_module(prefix => "content", uri => "http://purl.org/rss/1.0/modules/content/");

    my $res = $ril->get("get", {
        username => $ENV{RIL_USERNAME},
        password => $ENV{RIL_PASSWORD},
        state => 'unread',
    })->parse_response;

    for my $id (sort { $b <=> $a } keys %{$res->{list}}) {
        my $item = $res->{list}{$id};

        my $uri = URI->new("http://text.readitlaterlist.com/v2/text");
        $uri->query_form(apikey => $apikey, url => $item->{url}, mode => 'less', images => 1);

        warn "Fetching $id $item->{url}\n";
        my $html = $cache->get($id);
        unless ($html) {
            $html = LWP::Simple::get($uri);
            $cache->set($id => $html);
        }

        $html =~ s/&#(\d+);/chr($1)/eg;

        my $dt = DateTime->from_epoch(epoch => $item->{time_added});

        $feed->add_item(
            title => $item->{title},
            link => $item->{url},
            permaLink => $item->{url},
            content => { encoded => $html },
            pubDate => $format->format_datetime($dt),
        );
    }

    return [ 200, [ "Content-Type", "text/xml" ], [ Encode::encode_utf8($feed->as_string) ] ];
}

