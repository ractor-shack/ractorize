class RactorizedClass
  class << self
    attr_accessor :target_class

    def [](klass)
      puts "ractorizing #{klass}"
      ractorized_class = Class.new(RactorizedClass)
      ractorized_class.target_class = klass
      ractorized_class
    end

    def new(...)
      puts "creating a ractorized #{target_class}"
      Ractorize.ractorize_object(target_class.new(...))
    end

    def method_missing(method_name, ...)
      target_class.__send__(method_name, ...)
    end
  end
end
