# Managed thread usage example
threads = []
10.times do |i|
  threads << Thread.new do
    puts "worker #{i}"
    sleep 0.1
  end
end
threads.each(&:join)
