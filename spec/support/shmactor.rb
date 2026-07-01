require "shmactor"

if ENV["SHMACTOR"] == "true"
  Shmactor.activate!
  BaseRactor = Shmactor
end
