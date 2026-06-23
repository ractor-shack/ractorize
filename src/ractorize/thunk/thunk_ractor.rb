module Ractorize
  class Thunk < BasicObject
    ThunkRactor = ::Class.new(::ENV["SHMACTOR"] == "true" ? ::Shmactor : ::Ractor)

    class ThunkRactor
      class << self
        def new
          super do
            # SimpleCov seems to want us to handle the case where nothing matches but that would be an error
            # :nocov:
            case receive
            # :nocov:
            in :__close__
              # do nothing
            in :success, value
              value
            end
          end
        end
      end
    end
  end
end
