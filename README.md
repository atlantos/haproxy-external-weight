# haproxy-external-weight
Script to adjust Haproxy backends weight using backend metrics. By default uses average load, but can be redefined.

## Usage
* Add into haproxy.cfg:
```None
stats socket /var/lib/haproxy/stats mode 600 level admin
```
* Run haproxy-external-weight.rb:
```None
# haproxy-external-weight.rb 
Mon Aug 08 14:36:49 -0400 2016: changing weight for backend/server1 from 256 to 256
Mon Aug 08 14:36:49 -0400 2016: changing weight for backend/server2 from 153 to 175
```

## Internals

By default fetches 5 minutes average load using SSH from /proc/loadavg. You can define your own functions instead as
```Ruby
class MyHaproxy < LoadBalance::HaproxyGeneric
  def fetch_load
    # Fetch some remote metrics like load via snmp, number of connections, etc.
  end

  def calculate_weight(load)
    # Returns updated weight based on some metrics
  end
end

haproxy = LoadBalance::Haproxy.new
haproxy.load_weight
haproxy.apply_weight
```
