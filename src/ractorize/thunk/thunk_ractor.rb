module Ractorize
  class Thunk < BasicObject
    ThunkRactor = ::Class.new(::ENV["SHMACTOR"] == "true" ? ::Shmactor : ::Ractor)

    class ThunkRactor
      class << self
        def new
          super do
            case receive
            in :__close__
              raise ::ThunkRactor::ClosedError
            in :success, value
              value
            end
          end
        end
      end
    end
  end
end
