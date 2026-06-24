if ENV["SHMACTOR"] == "true"
  require "shmactor"

  Shmactor.activate!
  BaseRactor = Shmactor
end
