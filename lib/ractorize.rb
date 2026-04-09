# TODO: switch to autoload

files = Dir["#{__dir__}/../src/**/*.rb"]

files.sort_by! { |file| [file.count("/"), file.length, file] }
files.reverse!

files.each { require it }
