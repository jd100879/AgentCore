# Thread leak + blocking IO fixture
threads = []
10.times do
  threads << Thread.new do
    loop do
      sleep 1
      puts `ls #{ENV['USER_INPUT']}`
    end
  end
end

