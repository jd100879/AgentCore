worker = Thread.new do
  begin
    fetch_user
  rescue => e
    warn "background error: #{e.message}"
  end
end
worker.join

def fetch_user
  'user'
end
