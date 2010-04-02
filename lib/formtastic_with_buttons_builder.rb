class FormtasticWithButtonsBuilder < Formtastic::SemanticFormBuilder
  
  def submit(value = "Save changes", options = {})
    @template.content_tag(:button, value, options.reverse_merge(:type => "submit", :id => "#{object_name}_submit"))
  end
  
  def label(method, options_or_text=nil, options=nil)
    if options_or_text.is_a?(Hash)
      return "" if options_or_text[:label] == false
      options = options_or_text
      text = options.delete(:label)
    else
      text = options_or_text
      options ||= {}
    end
    
    text = create_safe_buffer do |buffer|
      buffer << (localized_string(method, text, :label) || humanized_attribute_name(method))
      buffer << required_or_optional_string(options.delete(:required))
    end

    # special case for boolean (checkbox) labels, which have a nested input
    text = create_safe_buffer { |b| b << (options.delete(:label_prefix_for_nested_input) || "") } + text
    input_name = options.delete(:input_name) || method
    super(input_name, text, options).gsub(/\?\s*\:\<\/label\>/, "?</label>").gsub(/\?\s*\:\s*\<abbr/, "? <abbr")
  end
  
  def boolean_input(method, options)
    super.gsub(":</label>", "</label>").gsub(": <abbr", " <abbr")
  end
  
  def pickups_input(method, options)
    collection   = options.delete(:collection) || []
    html_options = strip_formtastic_options(options).merge(options.delete(:input_html) || {})

    input_name = generate_association_input_name(method)
    value_as_class = options.delete(:value_as_class)
    input_ids = []
    selected_option_is_present = [:selected, :checked].any? { |k| options.key?(k) }
    selected_value = (options.key?(:checked) ? options[:checked] : options[:selected]) if selected_option_is_present

    list_item_content = collection.map do |c|
      at     = c.pickup_at
      value  = c.id
      pickup = c.pickup
      input_id = generate_html_id(input_name, value.to_s.gsub(/\s/, '_').gsub(/\W/, '').downcase)
      input_ids << input_id
      
      html_options[:checked] = selected_value == value if selected_option_is_present
      inner_label = pickup.name
      inner_label << " at #{::I18n.l(at, :format => :pickup_time)}" if at.present?
      li_content = template.content_tag(:label,
        "#{self.radio_button(input_name, value, html_options)} #{inner_label}",
        :for => input_id
      )

      li_options = value_as_class ? { :class => [method.to_s.singularize, value.to_s.downcase].join('_') } : {}
      template.content_tag(:li, li_content, li_options.merge(@template.pickup_data_options(pickup, html_options[:checked])))
    end

    field_set_and_list_wrapping_for_pickups(method, options.merge(:label_for => input_ids.first), list_item_content)
  end
  
  def date_or_datetime_input(method, options)
    position = { :year => 1, :month => 2, :day => 3, :hour => 4, :minute => 5, :second => 6 }
    i18n_date_order = ::I18n.t(:order, :scope => [:date])
    i18n_date_order = nil unless i18n_date_order.is_a?(Array)
    inputs   = options.delete(:order) || i18n_date_order || [:year, :month, :day]

    time_inputs = [:hour, :minute]
    time_inputs << [:second] if options[:include_seconds]

    list_items_capture = ""
    hidden_fields_capture = ""

    default_time = options.fetch(:default_time, ::Time.now)

    # Gets the datetime object. It can be a Fixnum, Date or Time, or nil.
    datetime = options[:selected] || (@object ? @object.send(method) : default_time) || default_time
    
    html_options = options.delete(:input_html) || {}
    input_ids    = []

    (inputs + time_inputs).each do |input|
      input_ids << input_id = generate_html_id(method, "#{position[input]}i")

      field_name = "#{method}(#{position[input]}i)"
      if options[:"discard_#{input}"]
        break if time_inputs.include?(input)

        hidden_value = datetime.respond_to?(input) ? datetime.send(input.to_sym) : datetime
        hidden_fields_capture << template.hidden_field_tag("#{@object_name}[#{field_name}]", (hidden_value || 1), :id => input_id)
      else
        opts = strip_formtastic_options(options).merge(:prefix => @object_name, :field_name => field_name, :default => datetime)
        item_label_text = ::I18n.t(input.to_s, :default => input.to_s.humanize, :scope => [:datetime, :prompts])
        
        list_items_capture << template.content_tag(:li,
          template.content_tag(:label, item_label_text, :for => input_id) <<
          template.send(:"select_#{input}", datetime, opts, html_options.merge(:id => input_id))
        )
      end
    end

    hidden_fields_capture << field_set_and_list_wrapping_for_method(method, options.merge(:label_for => input_ids.first), list_items_capture)
  end
  
  def field_set_and_list_wrapping_for_pickups(method, options, contents) #:nodoc:
    contents = contents.join if contents.respond_to?(:join)

    template.content_tag(:fieldset,
        template.content_tag(:legend,
            self.label(method, options_for_label(options).merge(:for => options.delete(:label_for))), :class => 'label'
          ) <<
        template.content_tag(:ol, contents, :id => "pickups-listing")
      )
  end
  
  
  def commit_button(*args)
    options = args.extract_options!
    text = options.delete(:label) || args.shift
    cancel_options = options.delete(:cancel)
    if @object
      key = @object.new_record? ? :create : :update
      object_name = @object.class.model_name.human
    else
      key = :submit
      object_name = @object_name.to_s.send(@@label_str_method)
    end

    text = (self.localized_string(key, text, :action, :model => object_name) ||
            ::Formtastic::I18n.t(key, :model => object_name)) unless text.is_a?(::String)

    button_html = options.delete(:button_html) || {}
    button_html.merge!(:class => [button_html[:class], key].compact.join(' '))
    element_class = ['commit', options.delete(:class)].compact.join(' ') # TODO: Add class reflecting on form action.
    accesskey = (options.delete(:accesskey) || @@default_commit_button_accesskey) unless button_html.has_key?(:accesskey)
    button_html = button_html.merge(:accesskey => accesskey) if accesskey 
    inner = self.submit(text, button_html)
    if cancel_options.present?
      inner << @template.content_tag(:span, "or", :class => "or")
      inner << @template.link_to(cancel_options.delete(:text), cancel_options.delete(:url), cancel_options)
    end
    template.content_tag(:li, inner, :class => element_class)
  end
  
  def error_sentence(errors) #:nodoc:
    error_text = errors.to_sentence.strip
    error_text << "." unless %w(? ! . :).include?(error_text[-1..-1])
    template.content_tag(:p, error_text, :class => 'inline-errors')
  end
  protected
  
  def create_safe_buffer
    buffer = defined?(ActiveSupport::SafeBuffer) ? ActiveSupport::SafeBuffer.new : ""
    yield buffer if block_given?
    buffer
  end
    
end