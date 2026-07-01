require_relative "../base_ractor"

module Ractorize
  class Thunk < BasicObject
    class ThunkRactor < ::BaseRactor
      class << self
        def new
          super do
            # SimpleCov seems to want us to handle the case where nothing matches but that would be an error
            # :nocov:
            case receive
            in :__close__
              # do nothing
            in :success, value
              value
            end
            # :nocov:
          end
        end
      end
    end
  end
end
