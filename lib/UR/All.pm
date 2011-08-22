package UR::All;

use strict;
use warnings;

our $VERSION = "0.34"; # UR $VERSION;

BEGIN { require above; };
use UR;

use Command;
use Command::DynamicSubCommands;
use Command::Test;
use Command::Test::Echo;
use Command::Test::Tree1;
use Command::Test::Tree1::Echo1;
use Command::Test::Tree1::Echo2;
use Command::Tree;
use Command::V1;
use Command::V2;
use Devel::callcount;
use UR::BoolExpr;
use UR::BoolExpr::Template;
use UR::BoolExpr::Template::And;
use UR::BoolExpr::Template::Composite;
use UR::BoolExpr::Template::Or;
use UR::BoolExpr::Template::PropertyComparison;
use UR::BoolExpr::Template::PropertyComparison::Between;
use UR::BoolExpr::Template::PropertyComparison::Equals;
use UR::BoolExpr::Template::PropertyComparison::False;
use UR::BoolExpr::Template::PropertyComparison::GreaterOrEqual;
use UR::BoolExpr::Template::PropertyComparison::GreaterThan;
use UR::BoolExpr::Template::PropertyComparison::In;
use UR::BoolExpr::Template::PropertyComparison::LessOrEqual;
use UR::BoolExpr::Template::PropertyComparison::LessThan;
use UR::BoolExpr::Template::PropertyComparison::Like;
use UR::BoolExpr::Template::PropertyComparison::Matches;
use UR::BoolExpr::Template::PropertyComparison::NotEqual;
use UR::BoolExpr::Template::PropertyComparison::NotIn;
use UR::BoolExpr::Template::PropertyComparison::NotLike;
use UR::BoolExpr::Template::PropertyComparison::True;
use UR::BoolExpr::Util;
use UR::Change;
use UR::Context;
use UR::Context::DefaultRoot;
use UR::Context::ObjectFabricator;
use UR::Context::Process;
use UR::Context::Root;
use UR::Context::Transaction;
use UR::DataSource;
use UR::DataSource::Code;
use UR::DataSource::CSV;
use UR::DataSource::Default;
use UR::DataSource::File;
use UR::DataSource::FileMux;
use UR::DataSource::Meta;
use UR::DataSource::MySQL;
use UR::DataSource::Oracle;
use UR::DataSource::Pg;
use UR::DataSource::RDBMS;
use UR::DataSource::RDBMS::BitmapIndex;
use UR::DataSource::RDBMS::Entity;
use UR::DataSource::RDBMS::FkConstraint;
use UR::DataSource::RDBMS::FkConstraintColumn;
use UR::DataSource::RDBMS::PkConstraintColumn;
use UR::DataSource::RDBMS::Table;
use UR::DataSource::RDBMS::Table::View::Default::Text;
use UR::DataSource::RDBMS::TableColumn;
use UR::DataSource::RDBMS::TableColumn::View::Default::Text;
use UR::DataSource::RDBMS::UniqueConstraintColumn;
use UR::DataSource::SQLite;
use UR::DataSource::ValueDomain;
use UR::DBI;
use UR::Debug;
use UR::DeletedRef;
use UR::Env::UR_COMMAND_DUMP_STATUS_MESSAGES;
use UR::Env::UR_CONTEXT_BASE;
use UR::Env::UR_CONTEXT_CACHE_SIZE_HIGHWATER;
use UR::Env::UR_CONTEXT_CACHE_SIZE_LOWWATER;
use UR::Env::UR_CONTEXT_MONITOR_QUERY;
use UR::Env::UR_CONTEXT_ROOT;
use UR::Env::UR_DBI_DUMP_STACK_ON_CONNECT;
use UR::Env::UR_DBI_EXPLAIN_SQL_CALLSTACK;
use UR::Env::UR_DBI_EXPLAIN_SQL_IF;
use UR::Env::UR_DBI_EXPLAIN_SQL_MATCH;
use UR::Env::UR_DBI_EXPLAIN_SQL_SLOW;
use UR::Env::UR_DBI_MONITOR_DML;
use UR::Env::UR_DBI_MONITOR_EVERY_FETCH;
use UR::Env::UR_DBI_MONITOR_SQL;
use UR::Env::UR_DBI_NO_COMMIT;
use UR::Env::UR_DEBUG_OBJECT_PRUNING;
use UR::Env::UR_DEBUG_OBJECT_RELEASE;
use UR::Env::UR_IGNORE;
use UR::Env::UR_NR_CPU;
use UR::Env::UR_STACK_DUMP_ON_DIE;
use UR::Env::UR_STACK_DUMP_ON_WARN;
use UR::Env::UR_TEST_FILLDB;
use UR::Env::UR_TEST_QUIET;
use UR::Env::UR_USE_ANY;
use UR::Env::UR_USE_DUMMY_AUTOGENERATED_IDS;
use UR::Env::UR_USED_LIBS;
use UR::Env::UR_USED_MODS;
use UR::Exit;
use UR::ModuleBase;
use UR::ModuleBuild;
use UR::ModuleConfig;
use UR::ModuleLoader;
use UR::Namespace;
use UR::Namespace::Command;
use UR::Namespace::Command::Base;
use UR::Namespace::Command::Define;
use UR::Namespace::Command::Define::Class;
use UR::Namespace::Command::Define::Datasource;
use UR::Namespace::Command::Define::Datasource::File;
use UR::Namespace::Command::Define::Datasource::Mysql;
use UR::Namespace::Command::Define::Datasource::Oracle;
use UR::Namespace::Command::Define::Datasource::Pg;
use UR::Namespace::Command::Define::Datasource::Rdbms;
use UR::Namespace::Command::Define::Datasource::RdbmsWithAuth;
use UR::Namespace::Command::Define::Datasource::Sqlite;
use UR::Namespace::Command::Define::Db;
use UR::Namespace::Command::Define::Namespace;
use UR::Namespace::Command::Describe;
use UR::Namespace::Command::Init;
use UR::Namespace::Command::List;
use UR::Namespace::Command::List::Classes;
use UR::Namespace::Command::List::Modules;
use UR::Namespace::Command::List::Objects;
use UR::Namespace::Command::Old;
use UR::Namespace::Command::Old::DiffRewrite;
use UR::Namespace::Command::Old::DiffUpdate;
use UR::Namespace::Command::Old::ExportDbicClasses;
use UR::Namespace::Command::Old::Info;
use UR::Namespace::Command::Old::Redescribe;
use UR::Namespace::Command::RunsOnModulesInTree;
use UR::Namespace::Command::Sys;
use UR::Namespace::Command::Sys::ClassBrowser;
use UR::Namespace::Command::Test;
use UR::Namespace::Command::Test::Callcount;
use UR::Namespace::Command::Test::Callcount::List;
use UR::Namespace::Command::Test::Compile;
use UR::Namespace::Command::Test::Eval;
use UR::Namespace::Command::Test::Run;
use UR::Namespace::Command::Test::TrackObjectRelease;
use UR::Namespace::Command::Test::Use;
use UR::Namespace::Command::Test::Window;
use UR::Namespace::Command::Update;
use UR::Namespace::Command::Update::ClassDiagram;
use UR::Namespace::Command::Update::ClassesFromDb;
use UR::Namespace::Command::Update::Pod;
use UR::Namespace::Command::Update::RenameClass;
use UR::Namespace::Command::Update::RewriteClassHeader;
use UR::Namespace::Command::Update::SchemaDiagram;
use UR::Namespace::Command::Update::TabCompletionSpec;
use UR::Object;
use UR::Object::Accessorized;
use UR::Object::Command::FetchAndDo;
use UR::Object::Command::List;
use UR::Object::Command::List::Style;
use UR::Object::Ghost;
use UR::Object::Index;
use UR::Object::Iterator;
use UR::Object::Property;
use UR::Object::Property::View::Default::Text;
use UR::Object::Property::View::DescriptionLineItem::Text;
use UR::Object::Property::View::ReferenceDescription::Text;
use UR::Object::Set;
use UR::Object::Set::View::Default::Json;
use UR::Object::Tag;
use UR::Object::Type;
use UR::Object::Type::AccessorWriter;
use UR::Object::Type::AccessorWriter::Product;
use UR::Object::Type::AccessorWriter::Sum;
use UR::Object::Type::Initializer;
use UR::Object::Type::InternalAPI;
use UR::Object::Type::ModuleWriter;
use UR::Object::Type::View::Default::Text;
use UR::Object::Value;
use UR::Object::View;
use UR::Object::View::Aspect;
use UR::Object::View::Default::Gtk;
use UR::Object::View::Default::Gtk2;
use UR::Object::View::Default::Json;
use UR::Object::View::Default::Text;
use UR::Object::View::Lister::Text;
use UR::Object::View::Toolkit;
use UR::Object::View::Toolkit::Text;
use UR::ObjectDeprecated;
use UR::ObjectV001removed;
use UR::ObjectV04removed;
use UR::Observer;
use UR::Report;
use UR::Service::RPC::Executer;
use UR::Service::RPC::Message;
use UR::Service::RPC::Server;
use UR::Service::RPC::TcpConnectionListener;
use UR::Singleton;
use UR::Test;
use UR::Util;
use UR::Value;
use UR::Value::ARRAY;
use UR::Value::Blob;
use UR::Value::CSV;
use UR::Value::DateTime;
use UR::Value::Decimal;
use UR::Value::DirectoryPath;
use UR::Value::FilePath;
use UR::Value::FilesystemPath;
use UR::Value::FOF;
use UR::Value::HASH;
use UR::Value::Integer;
use UR::Value::Iterator;
use UR::Value::Number;
use UR::Value::PerlReference;
use UR::Value::SCALAR;
use UR::Value::Set;
use UR::Value::Text;
use UR::Value::URL;
use UR::Vocabulary;

# optional elements
if (eval "use Net::HTTPServer") {
    my $rv = eval "UR::Namespace::View::SchemaBrowser::CgiApp;"
             && eval "use UR::Namespace::View::SchemaBrowser::CgiApp::Base;"
             && eval "use UR::Namespace::View::SchemaBrowser::CgiApp::Class;"
             && eval "use UR::Namespace::View::SchemaBrowser::CgiApp::File;"
             && eval "use UR::Namespace::View::SchemaBrowser::CgiApp::Index;"
             && eval "use UR::Namespace::View::SchemaBrowser::CgiApp::Schema;"
             && eval "use UR::Service::JsonRpcServer;";
    die $@ unless ($rv);
}


if (eval "use Xml::LibXSLT") {
    my $rv = eval "use UR::Object::View::Default::Html;"
             && eval "use UR::Object::View::Default::Xsl;"
             && eval "use UR::Object::Set::View::Default::Xml;"
             && eval "use UR::Object::View::Default::Xml;"
             && eval "use UR::Object::Type::View::Default::Xml;"
             ;
    die $@ unless ($rv);
}
 

1;

__END__

=pod

=head1 NAME

UR::All

=head1 SYNOPSIS

 use UR::All;

=head1 DESCRIPTION

This module exists to let software preload everything in the distribution

It is slower than "use UR", but is good for things like FastCGI servers.

=cut
