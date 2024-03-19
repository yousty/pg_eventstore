$(function(){
    "use strict";

    let initStreamFilterAutocomplete = function($filter) {
        let $contextSelect = $filter.find('select[name*="context"]');
        let $streamNameSelect = $filter.find('select[name*="stream_name"]');
        let $streamIdSelect = $filter.find('select[name*="stream_id"]');
        $contextSelect.select2({
            ajax: {
                url: $contextSelect.data('url'),
                processResults: function(data, params){
                    params.starting_id = data.pagination.starting_id;
                    data.results.forEach(function(contextAttrs){
                        contextAttrs.id = contextAttrs.context;
                        contextAttrs.text = contextAttrs.context;
                    });
                    return data;
                },
            }
        });
        $streamNameSelect.select2({
            ajax: {
                url: $streamNameSelect.data('url'),
                data: function (params) {
                    params.context = $contextSelect.val();

                    return params;
                },
                processResults: function(data, params){
                    params.starting_id = data.pagination.starting_id;
                    data.results.forEach(function(streamNameAttrs){
                        streamNameAttrs.id = streamNameAttrs.stream_name;
                        streamNameAttrs.text = streamNameAttrs.stream_name;
                    });
                    return data;
                },
            }
        });
        $streamIdSelect.select2({
            ajax: {
                url: $streamIdSelect.data('url'),
                data: function (params) {
                    params.context = $contextSelect.val();
                    params.stream_name = $streamNameSelect.val();

                    return params;
                },
                processResults: function(data, params){
                    params.starting_id = data.pagination.starting_id;
                    data.results.forEach(function(streamNameAttrs){
                        streamNameAttrs.id = streamNameAttrs.stream_id;
                        streamNameAttrs.text = streamNameAttrs.stream_id;
                    });
                    return data;
                },
            }
        });
    }

    let initEventTypeFilterAutocomplete = function($filter) {
        let $eventTypeSelect = $filter.find('select');
        $eventTypeSelect.select2({
            ajax: {
                url: $eventTypeSelect.data('url'),
                processResults: function(data, params){
                    params.starting_id = data.pagination.starting_id;
                    data.results.forEach(function(contextAttrs){
                        contextAttrs.id = contextAttrs.event_type;
                        contextAttrs.text = contextAttrs.event_type;
                    });
                    return data;
                },
            }
        });
    }

    // Toggle event's JSON data/metadata details
    $('.toggle-event-data').click(function(){
        $(this).parents('tr').next().toggleClass('d-none');
    });

    // Per page drop down
    $('#per_page_select').change(function(e){
        window.location.href = $(this).find('option:selected').data('url');
    });

    let $filtersForm = $('#filters-form');
    // Stream filter template
    let streamFilterTmpl = $('#stream-filter-tmpl').text();
    // Event type filter template
    let eventFilterTmpl = $('#event-type-filter-tmpl').text();

    // Remove filter button
    $filtersForm.on('click', '.remove-filter', function(){
        $(this).parents('.form-row').remove();
    });
    // Add stream filter button
    $filtersForm.on('click', '.add-stream-filter', function(){
        let filtersNum = $filtersForm.find('.stream-filters').children().length + '';
        $filtersForm.find('.stream-filters').append(streamFilterTmpl.replace(/%NUM%/g, filtersNum));
        initStreamFilterAutocomplete($filtersForm.find('.stream-filters').children().last());
    });
    // Add event type filter button
    $filtersForm.on('click', '.add-event-filter', function(){
        $filtersForm.find('.event-filters').append(eventFilterTmpl);
        initEventTypeFilterAutocomplete($filtersForm.find('.event-filters').children().last());
    });
    // Init select2 for stream filters which were initially rendered
    $filtersForm.find('.stream-filters').children().each(function(){
        initStreamFilterAutocomplete($(this));
    });
    // Init select2 for event type filters which were initially rendered
    $filtersForm.find('.event-filters').children().each(function(){
        initEventTypeFilterAutocomplete($(this));
    });
});
