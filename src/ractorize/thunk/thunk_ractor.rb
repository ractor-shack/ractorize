module Ractorize
  class Thunk < BasicObject
    class ThunkRactor < ::Ractor
      class << self
        def new
          super do
            case receive
            in :__close__
              raise ::Ractor::ClosedError
            in :success, value
            end

            value
          end
        end
      end
    end
  end
end
