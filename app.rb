require 'active_support/core_ext/numeric/time'
require 'oanda_api'
require 'pp'


class Base
  def initialize(token, env)
    @client = OandaAPI::Client::TokenClient.new(env, token)
  end

  def client
    @client
  end

  def candles(options={})
    params = {
      count: 30,
      alignmentTimezone: 'Asia/Tokyo',
      instrument: "USD_JPY",
      granularity: "H1",
      candle_format: "midpoint", # bidask, midpoint
      # start: (Time.now - 3600 * 24 * 3).utc.to_datetime.rfc3339
      end:   Time.now
    }
    params = params.merge(count: options[:count]) if !options[:count].nil?
    params = params.merge(instrument: options[:instrument]) if !options[:instrument].nil?
    params = params.merge(granularity: options[:granularity]) if !options[:granularity].nil?

    @candles ||= {}
    key_name = options.map{|a,b|"#{a}=#{b}"}.join("&")
    @candles[key_name] ||= client.candles(params).get
  end

  def order!(instrument, side, options={})
    params = {
      instrument: instrument,
      side: side,
      type: "market",
      units: 10_000,
      trailingStop: 20,
    }
    order = account.order(params).create
  end

  def tradable?
    orders.size == 0
  end

  def orders
    account.orders.get
  end

  def account
    client.account(account_id)
  end

  def account_id
    client.accounts.get.first.account_id
  end

end

class MyTrader < Base

  def run
    return unless tradable?

    order!('USD_JPY', 'buy')
    if long?(granularity: 'M15') && long?(granularity: 'M30') &&
       long?(granularity: 'H1') && long?(granularity: 'H4') &&
       long?(granularity: 'H12') && long?(granularity: 'D')
      order!('USD_JPY', 'buy')
    end


    if short?(granularity: 'M15') && short?(granularity: 'M30') &&
       short?(granularity: 'H1') && short?(granularity: 'H4') &&
       short?(granularity: 'H12') && short?(granularity: 'D')
      order!('USD_JPY', 'sell')
    end

  end

  private

  def long?(options)
    direction(options) < -3
  end

  def short?
    direction(options) > 3
  end

  def direction(options)
    data = bollinger_band(options)
    if data['std'] < data['s-3']
      -3
    elsif data['std'] < data['s-2']
      -2
    elsif data['std'] < data['s-1']
      -1
    elsif data['std'] > data['s+3']
      3
    elsif data['std'] > data['s+2']
      2
    elsif data['std'] > data['s+1']
      1
    else
      0
    end
  end

  def bollinger_band(options={})
    _candles = candles(options)
    n        = _candles.size
    key         = 'close'
    result = {
      open_avg:  0,
      close_avg: 0,
      high_avg:  0,
      low_avg:   0,
      open_sd:  0,
      close_sd: 0,
      high_sd:  0,
      low_sd:   0,
    }
    
    result = _candles.reduce(result) do |a, c|
      a[:open_avg]  += c.open_mid  / n
      a[:close_avg] += c.close_mid / n
      a[:high_avg]  += c.high_mid  / n
      a[:low_avg]   += c.low_mid   / n
      a
    end
    
    result = _candles.reduce(result) do |a, c|
      a[:open_sd]  += Math.sqrt((c.open_mid - a[:open_avg]) ** 2) / n
      a[:close_sd] += Math.sqrt((c.close_mid - a[:close_avg]) ** 2) / n
      a[:high_sd]  += Math.sqrt((c.high_mid - a[:high_avg]) ** 2) / n
      a[:low_sd]   += Math.sqrt((c.low_mid - a[:low_avg]) ** 2) / n
      a
    end
    # pp result
    
    data = {
      "about" => "size: #{candles.size} #{candles.granularity} #{candles.instrument}",
      "std"   => _candles.last.send("#{key}_mid"),
      "avg"   => result["#{key}_avg".to_sym],
      "s+1"   => result["#{key}_avg".to_sym] + (result["#{key}_sd".to_sym] * 1),
      "s+2"   => result["#{key}_avg".to_sym] + (result["#{key}_sd".to_sym] * 2),
      "s+3"   => result["#{key}_avg".to_sym] + (result["#{key}_sd".to_sym] * 3),
      "s-1"   => result["#{key}_avg".to_sym] - (result["#{key}_sd".to_sym] * 1),
      "s-2"   => result["#{key}_avg".to_sym] - (result["#{key}_sd".to_sym] * 2),
      "s-3"   => result["#{key}_avg".to_sym] - (result["#{key}_sd".to_sym] * 3),
    }
    data
  end
end



# env   = :live
env   = :practice

trader = MyTrader.new(ENV['OANDA_TOKEN'], env)
trader.run
