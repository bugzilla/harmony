requires 'Algorithm::BloomFilter', '0.02';
requires 'CGI', '4.31';
requires 'CGI::Compile';
requires 'CGI::Emulate::PSGI';
requires 'CPAN::Meta::Prereqs', '2.132830';
requires 'CPAN::Meta::Requirements', '2.121';
requires 'Class::XSAccessor', '1.18';
requires 'Crypt::CBC';
requires 'Crypt::DES';
requires 'Crypt::DES_EDE3';
requires 'DBI', '1.614';
requires 'DBIx::Class';
requires 'DBIx::Class::Helpers', '2.034002';
requires 'DBIx::Connector';
requires 'Daemon::Generic';
requires 'Date::Format', '2.23';
requires 'Date::Parse', '2.31';
requires 'DateTime', '0.75';
requires 'DateTime::TimeZone', '2.11';
requires 'Devel::NYTProf', '6.04';
requires 'Digest::SHA', '5.47';
requires 'EV', '4.0';
requires 'Email::Address';
requires 'Email::MIME', '1.904';
requires 'Email::Send', '1.911';
requires 'FFI::Platypus';
requires 'File::MimeInfo::Magic';
requires 'Future', '0.34';
requires 'HTML::Escape', '1.10';
requires 'HTML::Tree';
requires 'IO::Async', '0.71';
requires 'IO::Compress::Gzip';
requires 'IO::Scalar';
requires 'IPC::System::Simple';
requires 'JSON::MaybeXS', '1.003008';
requires 'JSON::Validator', '3.05';
requires 'JSON::XS', '2.0';
requires 'LWP::Protocol::https', '6.07';
requires 'LWP::UserAgent', '6.44';
requires 'LWP::UserAgent::Determined';
requires 'List::MoreUtils', '0.418';
requires 'Log::Dispatch', '2.67';
requires 'Log::Log4perl', '1.49';
requires 'Math::Random::ISAAC', 'v1.0.1';
requires 'Module::Metadata', '1.000033';
requires 'Module::Runtime', '0.014';
requires 'Mojo::JWT', '0.07';
requires 'MojoX::Log::Log4perl', '0.04';
requires 'Mojolicious', '8.42';
requires 'Moo', '2.002004';
requires 'MooX::StrictConstructor', '0.008';
requires 'Mozilla::CA', '20160104';
requires 'Net::DNS';
requires 'Package::Stash', '0.37';
requires 'Parse::CPAN::Meta', '1.44';
requires 'PerlX::Maybe';
requires 'Regexp::Common';
requires 'Role::Tiny', '2.000003';
requires 'Scope::Guard', '0.21';
requires 'Sereal', '4.004';
requires 'Sub::Quote', '2.005000';
requires 'Sys::Syslog';
requires 'Template', '2.24';
requires 'Text::CSV_XS', '1.26';
requires 'Text::Diff';
requires 'Throwable', '0.200013';
requires 'Tie::IxHash';
requires 'Type::Tiny', '1.004004';
requires 'URI', '1.55';
requires 'URI::Escape::XS', '0.14';
requires 'perl', '5.010001';
requires 'version', '0.87';
recommends 'Safe', '2.30';

on configure => sub {
    requires 'ExtUtils::MakeMaker', '7.22';
};

on build => sub {
    requires 'ExtUtils::MakeMaker', '7.22';
};

on test => sub {
    requires 'Capture::Tiny';
    requires 'DBD::SQLite', '1.29';
    requires 'DateTime::Format::SQLite', '0.11';
    requires 'Perl::Critic::Freenode';
    requires 'Perl::Critic::Policy::Documentation::RequirePodLinksIncludeText';
    requires 'Perl::Tidy', '20180220';
    requires 'Pod::Coverage';
    requires 'Selenium::Remote::Driver', '1.31';
    requires 'Test2::V0';
    requires 'Test::More';
    requires 'Test::Perl::Critic::Progressive';
    requires 'Test::Selenium::Firefox';
    requires 'Test::WWW::Selenium';
};
feature 'html_desc', 'More HTML in Product/Group Descriptions' => sub {
    requires 'HTML::Parser', '3.67';
    requires 'HTML::Scrubber';
};

feature 'jobqueue', 'Mail Queueing' => sub {
    requires 'Daemon::Generic';
    requires 'TheSchwartz', '1.10';
};

feature 'detect_charset', 'Automatic charset detection for text attachments' => sub {
    requires 'Encode', '2.21';
    requires 'Encode::Detect';
};

feature 's3', 'Amazon S3 Attachment Storage' => sub {
    requires 'Class::Accessor::Fast';
    requires 'URI::Escape';
    requires 'XML::Simple';
};

feature 'datadog', 'Data Dog support' => sub {
    requires 'DataDog::DogStatsd', '0.05';
};

feature 'oracle', 'Oracle database support' => sub {
    requires 'DBD::Oracle', '1.19';
};

feature 'typesniffer', 'Sniff MIME type of attachments' => sub {
    requires 'File::MimeInfo::Magic';
    requires 'IO::Scalar';
};

feature 'extension_push_optional', undef => sub {
    requires 'XML::Simple';
};

feature 'markdown', 'Markdown syntax support for comments' => sub {
    requires 'Text::MultiMarkdown', '1.000034';
    requires 'Unicode::GCString';
};

feature 'sqlite', 'SQLite database support' => sub {
    requires 'DBD::SQLite', '1.29';
    requires 'DateTime::Format::SQLite', '0.11';
};

feature 'linux_pid', 'Linux::PID' => sub {
    requires 'Linux::Pid';
};

feature 'jsonrpc', 'JSON-RPC Interface' => sub {
    requires 'JSON::RPC', '== 1.01';
    requires 'Test::Taint', '1.06';
};

feature 'oauth2_server', 'OAuth2 Server support' => sub {
    requires 'Mojolicious::Plugin::OAuth2::Server', '0.44';
};

feature 'pg', 'Postgres database support' => sub {
    requires 'DBD::Pg', 'v2.19.3';
};

feature 'linux_pdeath', 'Linux::Pdeathsig for a good parent/child relationships' => sub {
    requires 'Linux::Pdeathsig';
};

feature 'inbound_email', 'Inbound Email' => sub {
    requires 'Email::MIME::Attachment::Stripper';
    requires 'Email::Reply';
};

feature 'rest', 'REST Interface' => sub {
    requires 'JSON::RPC', '== 1.01';
    requires 'Test::Taint', '1.06';
};

feature 'better_xff', 'Improved behavior of MOJO_REVERSE_PROXY' => sub {
    requires 'Mojolicious::Plugin::ForwardedFor';
};

feature 'updates', 'Automatic Update Notifications' => sub {
    requires 'XML::Twig';
};

feature 'new_charts', 'New Charts' => sub {
    requires 'Chart::Lines', 'v2.4.10';
    requires 'GD', '1.20';
};

feature 'mysql', 'MySQL database support' => sub {
    requires 'DBD::mysql', '4.037';
    requires 'DateTime::Format::MySQL', '0.06';
};

feature 'argon2', 'Support hashing passwords with Argon2' => sub {
    requires 'Crypt::Argon2', '0.004';
};

feature 'mfa', 'Multi-Factor Authentication' => sub {
    requires 'Auth::GoogleAuth', '1.01';
    requires 'GD::Barcode::QRcode';
};

feature 'memcached', 'Memcached Support' => sub {
    requires 'Cache::Memcached::Fast', '0.17';
};

feature 'auth_ldap', 'LDAP Authentication' => sub {
    requires 'Net::LDAP';
};

feature 'old_charts', 'Old Charts' => sub {
    requires 'Chart::Lines', 'v2.4.10';
    requires 'GD', '1.20';
};

feature 'documentation', 'Documentation' => sub {
    requires 'File::Copy::Recursive';
    requires 'File::Which';
};

feature 'auth_radius', 'RADIUS Authentication' => sub {
    requires 'Authen::Radius';
};

feature 'moving', 'Move Bugs Between Installations' => sub {
    requires 'MIME::Parser', '5.406';
    requires 'XML::Twig';
};

feature 'sentry', 'Sentry Support' => sub {
    requires 'Log::Log4perl::Appender::Raven', '0.006';
};

feature 'linux_smaps', 'Linux::Smaps::Tiny for limiting memory usage' => sub {
    requires 'BSD::Resource';
    requires 'Linux::Smaps::Tiny';
};

feature 'chart_clicker', 'Support nice-looking charts' => sub {
    requires 'Chart::Clicker';
};

feature 'patch_viewer', 'Patch Viewer' => sub {
    requires 'PatchReader', 'v0.9.6';
};

feature 'graphical_reports', 'Graphical Reports' => sub {
    requires 'GD', '1.20';
    requires 'GD::Graph';
    requires 'GD::Text';
    requires 'Template::Plugin::GD::Image';
};

feature 'smtp_auth', 'SMTP Authentication' => sub {
    requires 'Authen::SASL';
};

feature 'alien_cmark', 'Support GitHub-flavored markdown' => sub {
    requires 'Alien::libcmark_gfm', '3';
};

feature 'xmlrpc', 'XML-RPC Interface' => sub {
    requires 'SOAP::Lite', '0.712';
    requires 'Test::Taint', '1.06';
    requires 'XMLRPC::Lite', '0.712';
};
