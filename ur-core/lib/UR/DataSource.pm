package UR::DataSource;
use strict;
use warnings;

require UR;
our $VERSION = "0.38"; # UR $VERSION;
use Sys::Hostname;

*namespace = \&get_namespace;

UR::Object::Type->define(
    class_name => 'UR::DataSource',
    is_abstract => 1,
    doc => 'A logical database, independent of prod/dev/testing considerations or login details.',
    has => [
        namespace => { calculate_from => ['id'] },
        is_connected => { is => 'Boolean', default_value => 0, is_optional => 1, is_transient => 1 },
    ],
);

our @CARP_NOT = qw(UR::Context UR::DataSource::QueryPlan);

sub define { shift->__define__(@_) }

sub get_namespace {
    my $class = shift->class;
    return substr($class,0,index($class,"::DataSource"));
}

sub get_name {
    my $class = shift->class;
    return lc(substr($class,index($class,"::DataSource")+14));
}

# The default used to be to force table/column/constraint/etc names to
# upper case when storing them in the MetaDB, and in the column_name
# metadata for properties.  The new behavior is to just use whatever the
# database supplies us when interrogating the data dictionary.
# For datasources/clases that still need the old behavior, override this
# to make the column_name metadata for properties forced to upper-case
sub table_and_column_names_are_upper_case { 0; }


# Basic, dumb data sources do not support joins within a single
# query.  Instead the Context logic can perform a cross datasource
# join within irs own code
sub does_support_joins { 0; }

# Most datasources do not support recursive queries
# Oracle and Postgres do, but in different ways
# For data sources without support, it'll have to do multiple queries
# to get all the data
sub does_support_recursive_queries { ''; }



our $use_dummy_autogenerated_ids;
*use_dummy_autogenerated_ids = \$ENV{UR_USE_DUMMY_AUTOGENERATED_IDS};
sub use_dummy_autogenerated_ids {
    # This allows the saved SQL from sync database to be comparable across executions.
    # It also 
    my $class = shift;
    if (@_) {
        ($use_dummy_autogenerated_ids) = @_;
    }
    $use_dummy_autogenerated_ids ||= 0;  # Replace undef with 0
    return $use_dummy_autogenerated_ids;
}

our $last_dummy_autogenerated_id;
sub next_dummy_autogenerated_id {   
    unless($last_dummy_autogenerated_id) {
        my $hostname = hostname();
        $hostname =~ /(\d+)/;
        my $id = $1 ? $1 : 1;
        $last_dummy_autogenerated_id = ($id * -10_000_000) - ($$ * 1_000);
    }

    #limit id to fit within 11 characters
    ($last_dummy_autogenerated_id) = $last_dummy_autogenerated_id =~ m/(-\d{1,10})/;

    return --$last_dummy_autogenerated_id;
}

sub autogenerate_new_object_id_for_class_name_and_rule {
    my $ds = shift;

    if (ref $ds) {
        $ds = ref($ds) . " ID " . $ds->id;
    }

    # Maybe we could use next_dummy_autogenerated_id instead?
    die "Data source $ds did not implement autogenerate_new_object_id_for_class_name_and_rule()";
}

# UR::Context needs to know if a data source supports savepoints
sub can_savepoint {
    my $class = ref($_[0]);
    die "Class $class didn't supply can_savepoint()";
}

sub set_savepoint {
    my $class = ref($_[0]);
    die "Class $class didn't supply set_savepoint, but can_savepoint is true";
}

sub rollback_to_savepoint {
    my $class = ref($_[0]);
    die "Class $class didn't supply rollback_to_savepoint, but can_savepoint is true";
}


sub _get_class_data_for_loading {
    my ($self, $class_meta) = @_;
    my $class_data = $class_meta->{loading_data_cache};
    unless ($class_data) {
        $class_data = $self->_generate_class_data_for_loading($class_meta);
    }
    return $class_data;
}
    
sub _resolve_query_plan {
    my ($self, $rule_template) = @_;
    my $qp = UR::DataSource::QueryPlan->get(
        rule_template => $rule_template,
        data_source => $self,
    );
    $qp->_init() unless $qp->_is_initialized;
    return $qp;
}

# Child classes can override this to return a different datasource
# depending on the rule passed in
sub resolve_data_sources_for_rule {
    return $_[0];
}
    
sub _generate_class_data_for_loading {
    my ($self, $class_meta) = @_;

    my $class_name = $class_meta->class_name;
    my $ghost_class = $class_name->ghost_class;

    my @all_id_property_names = $class_meta->all_id_property_names();
    my @id_properties = $class_meta->id_property_names;    
    my $id_property_sorter = $class_meta->id_property_sorter;    
    my @class_hierarchy = ($class_meta->class_name,$class_meta->ancestry_class_names);

    my @parent_class_objects = $class_meta->ancestry_class_metas;
    my $sub_classification_method_name;
    my ($sub_classification_meta_class_name, $subclassify_by);
    
    my @all_properties;
    my $first_table_name;
    for my $co ( $class_meta, @parent_class_objects ) {
        my $table_name = $co->table_name || '__default__';
        
        $first_table_name ||= $table_name;
        $sub_classification_method_name ||= $co->sub_classification_method_name;
        $sub_classification_meta_class_name ||= $co->sub_classification_meta_class_name;
        $subclassify_by   ||= $co->subclassify_by;
        
        my $sort_sub = sub ($$) { return $_[0]->property_name cmp $_[1]->property_name };
        push @all_properties, map { [$co, $_, $table_name, 0]} sort $sort_sub UR::Object::Property->get(class_name => $co->class_name);
    }

    my $sub_typing_property = $class_meta->subclassify_by;

    my $class_table_name = $class_meta->table_name;

    my $class_data = {
        class_name                          => $class_name,
        ghost_class                         => $class_name->ghost_class,
        
        parent_class_objects                => [$class_meta->ancestry_class_metas], ##
        sub_classification_method_name      => $sub_classification_method_name,
        sub_classification_meta_class_name  => $sub_classification_meta_class_name,
        subclassify_by    => $subclassify_by,
        
        all_properties                      => \@all_properties,
        all_id_property_names               => [$class_meta->all_id_property_names()],
        id_properties                       => [$class_meta->id_property_names],    
        id_property_sorter                  => $class_meta->id_property_sorter,    
        
        sub_typing_property                 => $sub_typing_property,
        
        # these seem like they go in the RDBMS subclass, but for now the 
        # "table" concept is stretched to mean any valid structure identifier 
        # within the datasource.
        first_table_name                    => $first_table_name,
        class_table_name                    => $class_table_name,
    };
    
    return $class_data;
}

sub _generate_loading_templates_arrayref {
    # Each entry represents a table alias in the query.
    # This accounts for different tables, or multiple occurrances 
    # of the same table in a join, by grouping by alias instead of
    # table.
    
    my $class = shift;
    my $db_cols = shift;
    my $obj_joins = shift;
    my $bxt = shift;

    use strict;
    use warnings;

    my %obj_joins_by_source_alias;
    if (0) { # ($obj_joins) {
        my @obj_joins = @$obj_joins;
        while (@obj_joins) {
            my $foreign_alias = shift @obj_joins;
            my $data = shift @obj_joins;
            for my $foreign_property_name (sort keys %$data) {
                next if $foreign_property_name eq '-is_required';
                
                my $source_alias = $data->{$foreign_property_name}{'link_alias'};
                my $detail = $obj_joins_by_source_alias{$source_alias}{$foreign_alias} ||= {};
                # warnings come from the above because we don't have 'link_alias' in filters.

                my $source_property_name = $data->{$foreign_property_name}{'link_property_name'};
                if ($source_property_name) {
                    # join
                    my $links = $detail->{links} ||= [];
                    push @$links, $foreign_property_name, $source_property_name;
                }

                if (exists $data->{value}) {
                    # filter
                    my $operator = $data->{operator};
                    my $value = $data->{value};
                    my $filter = $detail->{filter} ||= [];
                    my $key = $foreign_property_name;
                    $key .= ' ' . $operator if $operator;
                    push @$filter, $key, $value;
                }
            }
        }
    }
    else {
        #Carp::cluck("no obj joins???");
    }

    my %templates;
    my $pos = 0;
    my @templates;
    my %alias_object_num;
    for my $col_data (@$db_cols) {
        my ($class_obj, $prop, $table_alias, $object_num, $class_name) = @$col_data;
        unless (defined $object_num) {
            die "No object num for loading template data?!";
        }
        #Carp::confess() unless $table_alias;
        my $template = $templates[$object_num];
        unless ($template) {
            $template = {
                object_num => $object_num,
                table_alias => $table_alias,
                data_class_name => $class_obj->class_name,
                final_class_name => $class_name || $class_obj->class_name,
                property_names => [],                    
                column_positions => [],                    
                id_property_names => undef,
                id_column_positions => [],
                id_resolver => undef, # subref
            };
            $templates[$object_num] = $template;
            $alias_object_num{$table_alias} = $object_num;
        }
        push @{ $template->{property_names} }, $prop->property_name;
        push @{ $template->{column_positions} }, $pos;
        $pos++;
    }
    
    # Post-process the template objects a bit to get the exact id positions.
    for my $template (@templates) {
        next unless $template;  # This join may have resulted in no template?!
        my @id_property_names;
        for my $id_class_name ($template->{data_class_name}, $template->{data_class_name}->inheritance) {
            my $id_class_obj = UR::Object::Type->get(class_name => $id_class_name);
            last if @id_property_names = $id_class_obj->id_property_names;
        }
        $template->{id_property_names} = \@id_property_names;
        
        my @id_column_positions;
        for my $id_property_name (@id_property_names) {
            for my $n (0..$#{ $template->{property_names} }) {
                if ($template->{property_names}[$n] eq $id_property_name) {
                    push @id_column_positions, $template->{column_positions}[$n];
                    last;
                }
            }
        }
        $template->{id_column_positions} = \@id_column_positions;            
        
        if (@id_column_positions == 1) {
            $template->{id_resolver} = sub {
                return $_[0][$id_column_positions[0]];
            }
        }
        elsif (@id_column_positions > 1) {
            my $class_name = $template->{data_class_name};
            $template->{id_resolver} = sub {
                my $self = shift;
                return $class_name->__meta__->resolve_composite_id_from_ordered_values(@$self[@id_column_positions]);
            }                    
        }
        else {
            Carp::croak("Can't determine which columns will hold the ID property data for class "
                        . $template->{data_class_name} . ".  It's ID properties are (" . join(', ', @id_property_names)
                        . ") which do not appear in the class' property list (" . join(', ', @{$template->{'property_names'}}).")");
        }             

        my $source_alias = $template->{table_alias};
        if (0 and my $join_data_for_source_table = $obj_joins_by_source_alias{$source_alias}) {
            # there are joins which come from this entity to other entities
            # as these entities are loaded, remember the individual queries covered by this object returning
            # NOTE: when we join a <> b, we remember that we've loaded all of the b for a when _a_ loads, not b,
            # since it's possible that there ar zero of b, and we don't want to perform the query for b 
            my $source_object_num = $template->{object_num};
            my $source_class_name = $template->{data_class_name};
            my $next_joins = $template->{next_joins} ||= [];
            for my $foreign_alias (keys %$join_data_for_source_table) {
                my $foreign_object_num = $alias_object_num{$foreign_alias};
                Carp::confess("no alias for $foreign_alias?") if not defined $foreign_object_num;
                my $foreign_template = $templates[$foreign_object_num];
                my $foreign_class_name = $foreign_template->{data_class_name};

                my $join_data = $join_data_for_source_table->{$foreign_alias};
                my %links = map { $_ ? @$_ : () } $join_data->{links};
                my %filters = map { $_ ? @$_ : () } $join_data->{filters};
                
                my @keys = sort (keys %links, keys %filters);
                my @value_position_source_property;
                for (my $n = 0; $n < @keys; $n++) {
                    my $key = $keys[$n];
                    if ($links{$key} and $filters{$key}) {
                        Carp::confess("unexpected same key $key in filters and joins");
                    }
                    my $source_property_name = $links{$key};
                    next unless $source_property_name;
                    push @value_position_source_property, $n, $source_property_name; 
                }
                my $bx = $foreign_class_name->define_boolexpr(map { $_ => $filters{$_} } @keys);
                my ($bxt, @values) = $bx->template_and_values();
                push @$next_joins, [ $bxt->id, \@values, \@value_position_source_property ];
            }
        }
    }        

    return \@templates;        
}

sub create_iterator_closure_for_rule_template_and_values {
    my ($self, $rule_template, @values) = @_;
    my $rule = $rule_template->get_rule_for_values(@values);
    return $self->create_iterator_closure_for_rule($rule);
}

sub _reclassify_object_loading_info_for_new_class {
    my $self = shift;
    my $loading_info = shift;
    my $new_class = shift;

    my $new_info;
    %$new_info = %$loading_info;

    foreach my $template_id (keys %$loading_info) {

        my $target_class_rules = $loading_info->{$template_id};
        foreach my $rule_id (keys %$target_class_rules) {
            my $pos = index($rule_id,'/');
            $new_info->{$template_id}->{$new_class . "/" . substr($rule_id,$pos+1)} = 1;
        }
    }

    return $new_info;
}

sub _get_object_loading_info {
    my $self = shift;
    my $obj  = shift;
    my %param_load_hash;
    if ($obj->{'__load'}) {
        while( my($template_id, $rules) = each %{ $obj->{'__load'} } ) {
            foreach my $rule_id ( keys %$rules ) {
                $param_load_hash{$template_id}->{$rule_id} = $UR::Context::all_params_loaded->{$template_id}->{$rule_id};
            }
        }
    }
    return \%param_load_hash;
}


sub _add_object_loading_info {
    my $self = shift;
    my $obj = shift;
    my $param_load_hash = shift;

    while( my($template_id, $rules) = each %$param_load_hash) {
        foreach my $rule_id ( keys %$rules ) {
            $obj->{'__load'}->{$template_id}->{$rule_id} = $rules->{$rule_id};
        }
    }
}


# same as add_object_loading_info, but manipulates the data in $UR::Context::all_params_loaded
sub _record_that_loading_has_occurred {
    my $self = shift;
    my $param_load_hash = shift;

    while( my($template_id, $rules) = each %$param_load_hash) {
        foreach my $rule_id ( keys %$rules ) {
            $UR::Context::all_params_loaded->{$template_id}->{$rule_id} ||=
                $rules->{$rule_id};
        }
    }
}

sub _first_class_in_inheritance_with_a_table {
    # This is called once per subclass and cached in the subclass from then on.
    my $self = shift;
    my $class = shift;
    $class = ref($class) if ref($class);


    unless ($class) {
        Carp::confess("No class?");
    }
    my $class_object = $class->__meta__;
    my $found = "";
    for ($class_object, $class_object->ancestry_class_metas)
    {                
        if ($_->table_name)
        {
            $found = $_->class_name;
            last;
        }
    }
    #eval qq/
    #    package $class;
    #    sub _first_class_in_inheritance_with_a_table { 
    #        return '$found' if \$_[0] eq '$class';
    #        shift->SUPER::_first_class_in_inheritance_with_a_table(\@_);
    #    }
    #/;
    #die "Error setting data in subclass: $@" if $@;
    return $found;
}

sub _class_is_safe_to_rebless_from_parent_class {
    my ($self, $class, $was_loaded_as_this_parent_class) = @_;
    my $fcwt = $self->_first_class_in_inheritance_with_a_table($class);
    unless ($fcwt) {
        Carp::croak("Can't call _class_is_safe_to_rebless_from_parent_class(): Class $class has no parent classes with a table");
    }
    return ($was_loaded_as_this_parent_class->isa($fcwt));
}


sub _CopyToAlternateDB {
    # This is used to copy data loaded from the primary database into
    # a secondary database.  One use is for setting up an alternate DB
    # for testing by priming it from data from the "live" DB
    #
    # This is called from inside load() when the env var UR_TEST_FILLDB
    # is set.  For now, this alternate DB is always an SQLIte DB, and the
    # value of the env var is the base name of the file used as its storage.

    my($self,$load_class_name,$orig_dbh,$data) = @_;

    our %ALTERNATE_DB;
    my $dbname = $orig_dbh->{'Name'};

    my $dbh;
    if ($ALTERNATE_DB{$dbname}->{'dbh'}) {
        $dbh = $ALTERNATE_DB{$dbname}->{'dbh'};
    } else {
        my $filename = sprintf("%s.%s.sqlite", $ENV{'UR_TEST_FILLDB'}, $dbname);

        # FIXME - The right way to do this is to create a new UR::DataSource::SQLite object instead of making a DBI object directly
        unless ($dbh = $ALTERNATE_DB{$dbname}->{'dbh'} = DBI->connect("dbi:SQLite:dbname=$filename","","")) {
            $self->error_message("_CopyToAlternateDB: Can't DBI::connect() for filename $filename" . $DBI::errstr);
            return;
        }
        $dbh->{'AutoCommit'} = 0;
    }

    # Find out what tables this query will require
    my @isa = ($load_class_name);
    my(%tables,%class_tables);
    while (@isa) {
        my $class = shift @isa;
        next if $class_tables{$class};

        my $class_obj = $class->__meta__;
        next unless $class_obj;

        my $table_name = $class_obj->table_name;
        next unless $table_name;
        $class_tables{$class} = $table_name;

        foreach my $col ( $class_obj->direct_column_names ) {
            # FIXME Why are some of the returned column_names undef?
            next unless defined($col); # && defined($data->{$col});
            $tables{$table_name}->{$col} = $data->{$col} 
        }
        {   no strict 'refs';
            my @parents = @{$class . '::ISA'};
            push @isa, @parents;
        }
    }
    
    # For each parent class with a table, tell it to create itself
    foreach my $class ( keys %class_tables ) {
        next if (! $class_tables{$class} || $ALTERNATE_DB{$dbname}->{'tables'}->{$class_tables{$class}}++);

        my $class_obj = $class->__meta__();
        $class_obj->mk_table($dbh);
        #unless ($class_obj->mk_table($dbh)) {
        #    $dbh->rollback();
        #    return undef;
        #}
    }

    # Insert the data into the alternate DB
    foreach my $table_name ( keys %tables ) {
        my $sql = "INSERT INTO $table_name ";

        my $num_values = (values %{$tables{$table_name}});
        $sql .= "(" . join(',',keys %{$tables{$table_name}}) . ") VALUES (" . join(',', map {'?'} (1 .. $num_values)) . ")";
        my $sth = $dbh->prepare_cached($sql);
        unless ($sth) {
            $self->error_message("Error in prepare to alternate DB: $DBI::errstr\nSQL: $sql");
            $dbh->rollback();
            return undef;
        }

        unless ( $sth->execute(values %{$tables{$table_name}}) ) {
            $self->warning_message("Can't insert into $table_name in alternate DB: ".$DBI::errstr."\nSQL: $sql\nPARAMS: ".
                                   join(',',values %{$tables{$table_name}}));

            # We might just be inserting data that's already there...
            # This is the error message sqlite returns
            if ($DBI::errstr !~ m/column (\w+) is not unique/i) {
                $dbh->rollback();
                return undef;
            }
        }
    }

    $dbh->commit();
    
    1;
}

sub _get_current_entities {
    my $self = shift;
    my @class_meta = UR::Object::Type->is_loaded(
        data_source_id => $self->id
    );
    my @objects;
    for my $class_meta (@class_meta) {
        next unless $class_meta->generated();  # Ungenerated classes won't have any instances
        my $class_name = $class_meta->class_name;
        push @objects, $UR::Context::current->all_objects_loaded($class_name);
    }
    return @objects;
}


sub _prepare_for_lob { };

sub _set_specified_objects_saved_uncommitted {
    my ($self,$objects_arrayref) = @_;
    # Sets an objects as though the has been saved but tha changes have not been committed.
    # This is called automatically by _sync_databases.

    my %objects_by_class;
    my $class_name;
    for my $object (@$objects_arrayref) {
        $class_name = ref($object);
        $objects_by_class{$class_name} ||= [];
        push @{ $objects_by_class{$class_name} }, $object;
    }

    for my $class_name (sort keys %objects_by_class) {
        my $class_object = $class_name->__meta__;
        my @property_names =
            map { $_->property_name }
            grep { $_->column_name }
            $class_object->all_property_metas;

        for my $object (@{ $objects_by_class{$class_name} }) {
            $object->{db_saved_uncommitted} ||= {};
            my $db_saved_uncommitted = $object->{db_saved_uncommitted};
            for my $property ( @property_names ) {
                $db_saved_uncommitted->{$property} = $object->$property;
            }
        }
    }
    return 1;
}

sub _set_all_objects_saved_committed {
    # called by UR::DBI on commit
    my $self = shift;
    return $self->_set_all_specified_objects_saved_committed($self->_get_current_entities);
}

sub _set_all_specified_objects_saved_committed {
    my $self = shift;
    my @objects = @_;

    # Two step process... set saved and committed, then fire commit observers.
    # Doing so prevents problems should any of the observers themselves commit.
    my @saved_objects;
    for my $obj (@objects) {
        my $saved = $self->_set_object_saved_committed($obj);
        push @saved_objects, $saved if $saved;
    }

    for my $obj (@saved_objects) {
        next if $obj->isa('UR::DeletedRef');
        $obj->__signal_change__('commit');
        if ($obj->isa('UR::Object::Ghost')) {
            $UR::Context::current->_abandon_object($obj);
        }
    }

    return scalar(@objects) || "0 but true";
}

sub _set_object_saved_committed {
    # called by the above, and some test cases
    my ($self, $object) = @_;
    if ($object->{db_saved_uncommitted}) {
        unless ($object->isa('UR::Object::Ghost')) {
            %{ $object->{db_committed} } = (
                ($object->{db_committed} ? %{ $object->{db_committed} } : ()),
                %{ $object->{db_saved_uncommitted} }
            );
            delete $object->{db_saved_uncommitted};
        }
        return $object;
    }
    else {
        return;
    }
}

sub _set_all_objects_saved_rolled_back {
    # called by UR::DBI on commit
    my $self = shift;
    my @objects = $self->_get_current_entities;
    for my $obj (@objects)  {
        unless ($self->_set_object_saved_rolled_back($obj)) {
            die "An error occurred setting " . $obj->__display_name__
             . " to match the rolled-back database state.  Exiting...";
        }
    }
}


sub _set_object_saved_rolled_back {
    # called by the above, and some test cases
    my ($self,$object) = @_;
    delete $object->{db_saved_uncommitted};
    return $object;
}


# These are part of the basic DataSource API.  Subclasses will want to override these

sub _sync_database {
    my $class = shift;
    my %args = @_;
    $class = ref($class) || $class;

    $class->warning_message("Data source $class does not support saving objects to storage.  " . 
                            scalar(@{$args{'changed_objects'}}) . " objects will not be saved");
    return 1;
}

sub commit {
    my $class = shift;
    my %args = @_;
    $class = ref($class) || $class;

    #$class->warning_message("commit() ignored for data source $class");
    return 1;
}

sub rollback {
    my $class = shift;
    my %args = @_;
    $class = ref($class) || $class;

    $class->warning_message("rollback() ignored for data source $class");
    return 1;
}

# basic, dumb datasources do not have a handle
sub get_default_handle {
    return;
}

# When the class initializer is create property objects, it will
# auto-fill-in column_name if the class definition has a table_name.
# File-based data sources do not have tables (and so classes using them
# do not have table_names), but the properties still need column_names
# so loading works properly.
# For now, only UR::DataSource::File and ::FileMux set this.
# FIXME this method's existence is ugly.  Find a better way to fill in
# column_name for those properties, or fix the data sources to not
# require column_names to be set by the initializer
sub initializer_should_create_column_name_for_class_properties {
    return 0;
}


# Subclasses should override this.
# It's called by the class initializer when the data_source property in a class
# definition contains a hashref with an 'is' key.  The method should accept this
# hashref, create a data_source instance (if appropriate) and return the class_name
# of this new datasource.
sub create_from_inline_class_data {
    my ($class,$class_data,$ds_data) = @_;
    my %ds_data = %$ds_data;
    my $ds_class_name = delete $ds_data{is};
    unless (my $ds_class_meta = UR::Object::Type->get($ds_class_name)) {
        die "No class $ds_class_name found!";
    }
    my $ds = $ds_class_name->__define__(%ds_data);
    unless ($ds) {
        die "Failed to construct $ds_class_name: " . $ds_class_name->error_message();
    }
    return $ds;
}

sub ur_data_type_for_data_source_data_type {
    my($class,$type) = @_;

    return [undef,undef];   # The default that should give reasonable behavior
}


# This is a no-op in the base class.  If the DataSource needs to do any
# database handle disconnection or other housekeeping prior to a fork, this should be
# the place to do it.
sub prepare_for_fork {
    my $self = shift;
    
    return 1;
}

# this is also a no-op here.  If a DataSource needs to do any work after forking
# this is the place for that.  For example, a file based data source will need to
# re-open the file and seek() to the location it was at before the fork happened.
sub finish_up_after_fork {
    my $self = shift;

    return 1;
}

1;