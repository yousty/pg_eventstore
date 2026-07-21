#include "ruby.h"
#include "ruby/st.h"

/*
  Loops through the given array of partition ids to find an index at which we have up to max_partitions_per_call unique
  partitions. Ruby representation of this implementation looks like this:
    def range_to_slice2(partition_ids, max_partitions_per_call)
      return (0..) if partition_ids.size <= max_partitions_per_call

      partitions_map = {}
      latest_index = nil
      partition_ids.each_with_index do |partition_id, index|
        partitions_map[partition_id] = true
        if partitions_map.size > max_partitions_per_call
          latest_index = index - 1
          break
        end
      end
      0..latest_index
    end
  It was extracted into C extension because of performance of ruby loops - they are deadly slow comparing to C loops.
  The performance gain is x5-x15 times faster comparing to ruby implementation. Because we need to do this operation on
  each read command - it worth having it here.
*/
static VALUE
range_to_slice(VALUE self, VALUE partition_ids, VALUE max_partitions_per_call)
{
    long partition_ids_size = RARRAY_LEN(partition_ids);
    const VALUE *partition_id_values;
    long max_partitions = NUM2LONG(max_partitions_per_call);
    st_table *unique_partition_ids;
    long unique_partitions = 0;
    long index;
    VALUE latest_index = Qnil;

    if (partition_ids_size <= max_partitions) {
        return rb_range_new(INT2FIX(0), Qnil, 0);
    }

    partition_id_values = RARRAY_CONST_PTR(partition_ids);
    unique_partition_ids = st_init_numtable();

    for (index = 0; index < partition_ids_size; index++) {
        st_data_t partition_id = (st_data_t)partition_id_values[index];

        if (!st_lookup(unique_partition_ids, partition_id, NULL)) {
            st_insert(unique_partition_ids, partition_id, (st_data_t)1);
            unique_partitions++;
        }

        if (unique_partitions > max_partitions) {
            latest_index = LONG2NUM(index - 1);
            break;
        }
    }

    st_free_table(unique_partition_ids);

    return rb_range_new(INT2FIX(0), latest_index, 0);
}

void
Init_pg_eventstore_ext(void)
{
    VALUE pg_eventstore = rb_define_module("PgEventstore");
    VALUE utils = rb_define_class_under(pg_eventstore, "Utils", rb_cObject);

    rb_define_singleton_method(
        utils,
        "range_to_slice",
        range_to_slice,
        2
    );
}
