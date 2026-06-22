module Ractorize
  class Thunk < BasicObject
    ThunkRactor = ::Class.new(::ENV["SHMACTOR"] == "true" ? ::Shmactor : ::Ractor)

    class ThunkRactor
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
