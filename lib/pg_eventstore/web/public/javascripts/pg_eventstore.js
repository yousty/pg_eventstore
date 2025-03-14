$(function(){
    "use strict";

    let initStreamFilterAutocomplete = function($filter) {
        let $contextSelect = $filter.find('select[name*="context"]');
        let $streamNameSelect = $filter.find('select[name*="stream_name"]');
        let $streamIdSelect = $filter.find('select[name*="stream_id"]');

        let removeDeleteBtn = function(){
            $filter.find('.delete-stream').remove();
        }

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
            },
            allowClear: true
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
            },
            allowClear: true
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
            },
            allowClear: true
        });
        $contextSelect.on('change.select2', removeDeleteBtn);
        $streamNameSelect.on('change.select2', removeDeleteBtn);
        $streamIdSelect.on('change.select2', removeDeleteBtn);
    }

    let initSystemStreamFilterAutocomplete = function($filter){
        let $streamNameSelect = $filter.find('select');
        $streamNameSelect.select2({
            allowClear: true
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
            },
            allowClear: true
        });
    }

    // Per page drop down
    $('#per_page_select').change(function(e){
        window.location.href = $(this).find('option:selected').data('url');
    });

    let $filtersForm = $('#filters-form');
    // Stream filter template
    let streamFilterTmpl = $('#stream-filter-tmpl').text();
    // System stream filter template
    let systemStreamFilterTmpl = $('#system-stream-filter-tmpl').text();
    // Event type filter template
    let eventFilterTmpl = $('#event-type-filter-tmpl').text();

    // Remove filter button
    $filtersForm.on('click', '.remove-filter', function(){
        $(this).parents('.form-row').remove();
    });
    // "Add stream filter" button
    $filtersForm.on('click', '.add-stream-filter', function(){
        let filtersNum = $filtersForm.find('.stream-filters').children().length + '';
        $filtersForm.find('.stream-filters').append(streamFilterTmpl.replace(/%NUM%/g, filtersNum));
        initStreamFilterAutocomplete($filtersForm.find('.stream-filters').children().last());
    });
    // "Add system stream filter" button
    $filtersForm.on('click', '.add-system-stream-filter', function(){
        if($filtersForm.find('.system-stream-filter').children().length > 0)
            return;

        $filtersForm.find('.system-stream-filter').append(systemStreamFilterTmpl);
        initSystemStreamFilterAutocomplete($filtersForm.find('.system-stream-filter').children().last());
    });
    // "Add event type filter" button
    $filtersForm.on('click', '.add-event-filter', function(){
        $filtersForm.find('.event-filters').append(eventFilterTmpl);
        initEventTypeFilterAutocomplete($filtersForm.find('.event-filters').children().last());
    });

    // Init select2 for stream filters which were initially rendered
    $filtersForm.find('.stream-filters').children().each(function(){
        initStreamFilterAutocomplete($(this));
    });
    // Init select2 for system stream filter which were initially rendered
    $filtersForm.find('.system-stream-filter').children().each(function(){
        initSystemStreamFilterAutocomplete($(this));
    });
    // Init select2 for event type filters which were initially rendered
    $filtersForm.find('.event-filters').children().each(function(){
        initEventTypeFilterAutocomplete($(this));
    });

    // Automatically refresh events list every two seconds
    let autoRefreshInterval;
    $('#auto-refresh').change(function(){
       if($(this).is(':checked')) {
           autoRefreshInterval = setInterval(function(){
               $.getJSON(window.location.href).success(function(response, textStatus, xhr){
                   if(textStatus === 'success') {
                       $('#events-table').find('tbody').html(response.events);
                       $('#total-count').html(response.total_count);
                       $('#pagination').html(response.pagination);
                   }
               });
           }, 2000);
       } else {
           clearInterval(autoRefreshInterval);
       }
    });

    // Resolve links checkbox
    $('#resolve-link-tos').change(function(){
        if($(this).is(':checked')) {
            window.location.href = $(this).data('url-checked');
        } else {
            window.location.href = $(this).data('url-unchecked');
        }
    });

    // Toggle event's JSON data/metadata details
    $('#events-table').on('click', '.toggle-event-data', function(){
        $(this).parents('tr').next().toggleClass('d-none');
    });

    // When user navigates through SubscriptionsSet-s tabs - also change a hash of the url. Its value is send when
    // clicking on a[data-method] links
    $('.set-tab').click(function(e){
        window.location.hash = $(this).attr('href');
    })
    // Open correct SubscriptionsSet tab on page load based on location's hash value. So, e.g., if you navigated to
    // #set-1 SubscriptionsSet, then, on page reload - the correct tab will be opened
    if(window.location.hash !== "") {
        let link = $(`.set-tab[href="${window.location.hash}"]`).get(0);
        if(link)
            link.click();
    }
});

// Confirmation dialog and data-method handling functional
$(function(){
    "use strict";

    let $confirmationModal = $('#confirmation-modal');

    $confirmationModal.on('hide.bs.modal', function(){
        $(this).find('.modal-title').html('');
        $(this).find('.modal-body').html('');
        $(this).find('.confirm').off();
    });
    let showConfirmation = function(el, callback){
        let $el = $(el);
        $confirmationModal.find('.modal-body').html($el.data('confirm'));
        $confirmationModal.find('.modal-title').html($el.data('confirm-title'));
        $confirmationModal.modal('show');
        $confirmationModal.one('click', '.confirm', callback);
    }

    let handleMethod = function(el){
        let $el = $(el);
        let href = $el.attr('href');
        let method = $el.data('method') || 'GET';

        if(method === 'GET') {
            window.location.href = href;
        }else{
            let $form = $(`<form method="${method}" action="${href}"></form>`);
            let hashInput = `<input name="hash" value="${window.location.hash}" type="hidden" />`;

            $form.append(hashInput);
            $form.hide().appendTo('body');
            $form.submit();
        }
    }

    $('body').on('click', 'a[data-confirm], a[data-method]', function(e){
        e.preventDefault();
        if($(this).data('confirm')) {
            showConfirmation(e.target, function(){
                handleMethod(e.target);
            });
            return;
        }
        handleMethod(e.target);
    });
});

// Reset position action handling
$(function(){
    "use strict";

    let $resetPositionModal = $('#reset-position-modal');

    $resetPositionModal.on('hide.bs.modal', function(){
        $(this).find('.subscription-name').html('');
        $(this).find('form').removeAttr('action');
    });

    $resetPositionModal.on('show.bs.modal', function(e){
       let $clickedLink = $(e.relatedTarget);
        $(this).find('.subscription-name').html($clickedLink.data('subscription-name'));
        $(this).find('form').attr('action', $clickedLink.data('url'));
    });
});

// Display subscriptions of the selected state
$(function(){
    "use strict";

    let $subscriptionsState = $('#subscriptions-state');
    $subscriptionsState.change(function(){
       let $selected = $(this).find('option:selected');
       window.location.href = $selected.data('url');
    });
});

// Event deletion handling
$(function(){
   "use strict";

   let $deleteEventModal = $('#delete-event-modal');

    $deleteEventModal.on('hide.bs.modal', function(){
        $(this).find('.global-position-text').html('');
        $(this).find('form').removeAttr('action');
    });

    $deleteEventModal.on('show.bs.modal', function(e){
        let $clickedLink = $(e.relatedTarget);
        $(this).find('.global-position-text').html($clickedLink.data('global-position'));
        $(this).find('form').attr('action', $clickedLink.data('url'));
    });
});

// Flash messages
$(function () {
    "use strict";

    let message = Cookies.get(window.flashMessageCookie);
    if (!message)
        return;

    try {
        message = Uint8Array.fromBase64(message, { alphabet: "base64url" });
        message = new TextDecoder().decode(message);
        message = JSON.parse(message);
    } catch (e) {
        console.debug(message);
        console.debug(e);
        Cookies.remove(window.flashMessageCookie);
        return;
    }

    let $flashMessage = $('#flash-message');
    let alertClass;
    switch(message.kind) {
        case "error":
            alertClass = "alert-danger";
            break;
        case "warning":
            alertClass = "alert-warning";
            break;
        case "success":
            alertClass = "alert-success";
            break;
        default:
            alertClass = "alert-light";
    }

    $flashMessage.find('.message').text(message.message);
    $flashMessage.addClass(alertClass).removeClass('d-none');
    Cookies.remove(window.flashMessageCookie);
});
