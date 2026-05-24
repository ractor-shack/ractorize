module Ractorize
  class RactorizedClass
    class << self
      def [](klass)
        ractorized_class = Class.new(RactorizedClass)
        ractorized_class.define_singleton_method(:target_class, Ractor.shareable_proc { klass })
        ractorized_class
      end

      def new(...)
        RactorizedObject.new(:class, target_class, ...)
      end

      def method_missing(method_name, ...)
        target_class.__send__(method_name, ...)
      end

      def respond_to_missing?(method_name, include_all = false)
        target_class.respond_to?(method_name, include_all)
      end
    end
  end
end
