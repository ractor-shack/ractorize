if ENV["SHMACTOR"] == "true"
  require "shmactor"
  BaseRactor = Shmactor
end
