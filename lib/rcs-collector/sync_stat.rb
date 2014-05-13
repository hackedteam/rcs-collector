module RCS
  module Collector
    class SyncStat

      attr_accessor :total

      def initialize
        @total = 0
        @transferred = 0
        @transferred_size = 0
        @timeout = false
      end

      def ended
        @ended_at = timestamp
      end

      def timedout
        @timeout = true
        ended
      end

      def started
        @started_at = timestamp
      end

      def update(evidence_size, num: 1)
        @transferred += num
        @transferred_size += evidence_size

        transfer_time = timestamp - @started_at

        # bytes/sec
        @speed = @transferred_size / transfer_time
      end

      def to_hash
        {total: @total, count: @transferred, begin: @started_at,
          end: @ended_at, speed: @speed, timeout: @timeout, size: @transferred_size}
      end

      alias :as_json :to_hash

      def to_json(*args)
        as_json.to_json(args)
      end

      def timestamp
        Time.now.utc.to_i
      end
    end
  end
end
