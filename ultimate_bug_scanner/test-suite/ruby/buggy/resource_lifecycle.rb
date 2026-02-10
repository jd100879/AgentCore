Thread.new do
  sleep 0.1
end

file = File.open("/tmp/leaky.txt", "w")
file.write("hello")
# No join or close
