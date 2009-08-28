require 'tyrannical'
$: << File.dirname(__FILE__)
require '_thing'

Tyrannical.connection = TokyoTyrant::Table.new

class Example < Tyrannical
  attribute :id, :integer
  attribute :num, :integer
  attribute :starts_at, :type => :time, :default => proc{ Time.now }
  attribute :stuff, :type => :raw
  attribute(:thing){ |v| Thing.from_string(v) }

  validates_presence_of :num
  validates_numericality_of :num  

  # Not implemented yet
  def before_save
    attributes[:stuff] = Marshal.dump(attributes[:stuff])
  end
end
