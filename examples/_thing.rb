class Thing
  attr_accessor :one
  @one = ""
  attr_accessor :two
  @two = ""

  def initialize(one, two)
    @one, @two = one, two
  end

  def to_s
    "#{one}:#{two}"
  end

  def self.from_string(s)
    new(*s.split(":"))
  end
end
