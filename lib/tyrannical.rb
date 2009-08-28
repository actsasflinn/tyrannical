require 'tokyo_tyrant' # http://github.com/actsasflinn/ruby-tokyotyrant/tree

require 'active_support'
require 'active_model'

$: << File.dirname(__FILE__)

require 'extensions/false_class'
require 'extensions/true_class'
require 'extensions/time'

class Tyrannical
  include ActiveModel::Validations

  # Stores the default scope for the class
  class_inheritable_accessor :connection

  class_inheritable_accessor :type_casts
  self.type_casts = {
    :integer     => proc{ |v| Integer(v) },
    :float       => proc{ |v| Float(v) },
    :time        => proc{ |v| Time.at(v.to_i) },
    :date        => proc{ |v| Date.parse(v) },
    :boolean     => proc{ |v| v == "0" ? false : true },
    :raw         => proc{ |v| Marshal.load(v) }
  }

  class_inheritable_accessor :columns
  self.columns = {}

  class_inheritable_accessor :protected_attributes
  self.protected_attributes = [:__id, :type]

  attr_accessor :attributes
  @attributes = {}

  attr_accessor :new_record

  validates_presence_of :id

  def initialize(attributes = {})
    @attributes = attributes
    @new_record = true
    set_defaults
  end

  def set_defaults
    self.class.columns.each{ |name, options|
      if attributes[name].blank?
        if options[:default].respond_to?(:call)
          attributes[name] = options[:default].call
        else
          attributes[name] = options[:default]
        end
      end
    }
  end

  def cast_types
    self.class.columns.each{ |name, options|
      if attributes[name] && options[:type].respond_to?(:call)
        attributes[name] = options[:type].call(attributes[name])
      end
    }
  end

  def new_record?
    @new_record
  end

  def [](k)
    attributes[k.to_sym]
  end

  def []=(k,v)
    attributes[k.to_sym] = v
  end

  def to_h
    attributes
  end

  def id
    attributes[:id] ||= connection.genuid
  end

  def key
    @key ||= self.class.key(id)
  end

  def save
    return false unless valid?
    value = self.to_h.merge(:type => self.class.type_name)
    self.new_record = !connection.put(key, value)
    self
  end

  def method_missing(name, *args, &block)
    attribute_name = name.to_s.gsub(/=$/,'').to_sym
    if attributes.include?(attribute_name)
      if name.to_s.match(/=$/)
        self.class.define_writer(attribute_name)
      else
        self.class.define_reader(attribute_name)
      end
      send(name, *args)
    else
      super
    end
  end

  class << self
    def instantiate(h)
      object = allocate
      h.symbolize_keys!
      protected_attributes.each{ |k| h.delete(k) }
      object.instance_variable_set("@attributes", h)
      object.instance_variable_set("@new_record", false)
      object.set_defaults
      object.cast_types
      object
    end

    def create(attributes = {})
      object = new(attributes)
      object.save
      object
    end

    # Define an attribute
    # attribute(:foo)
    # attribute(:foo, :default => "Bar")
    # attribute(:foo, :integer)
    # attribute(:foo, :type => integer, :default => 1)
    # attribute(:foo, :type => :raw)
    # attribute(:foo, :type => proc{ |v| Thing.from_string(v) })
    # attribute(:foo){ |v| Thing.from_string(v) }
    #
    def attribute(name, options = {}, &block)
      cast, options = options.is_a?(Hash) ? [options.delete(:type), options] : [options, {}]
      if block_given?
        options[:type] = block
      elsif cast.is_a?(Symbol) && type_casts.include?(cast)
        options[:type] = type_casts[cast]
      end
      columns[name] = options

      # this will need to be a little more formal
      define_reader(name)
      define_writer(name)
    end

    def define_reader(name)
      define_method(name){ attributes[name] } unless method_defined?(name)
    end

    def define_writer(name)
      writer_name = "#{name}=".to_sym
      define_method(writer_name){ |value| attributes[name] = value } unless method_defined?(writer_name)
    end

    def type_name
      @type_name ||= name.tableize
    end

    def key(id)
      "#{type_name}/#{id}"
    end

    def get(k)
      if res = connection.get(key(k))
        instantiate(res)
      end
    end
    alias_method :[], :get

    def get!(k)
      if res = get(k)
        res
      else
        raise "No such record"
      end
    end

    def all(*keys, &block)
      if block_given? || keys.size.zero?
        results = connection.prepare_query(&block).condition(:type, :streq, type_name).get
      else
        keys = keys.collect{ |key| key(key) }
        results = connection.mget(keys)
        # if Ruby 1.8.x?
        ordered_results = keys.inject([]){ |res, k| results[k] ? res << results[k] : res }
        results = ordered_results
      end
      results.collect{ |object| instantiate(object) }
    end

    def count(&block)
      connection.prepare_query(&block).condition(:type, :streq, type_name).count
    end

    def destroy(*keys, &block)
      if block_given?
        connection.prepare_query(&block).condition(:type, :streq, type_name).delete
      else
        keys.each{ |key| connection.delete(key(key)) }
      end
    end

    def destroy_all
      connection.query.condition(:type, :streq, type_name).delete
    end
  end
end