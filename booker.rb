#!/usr/bin/env ruby

# Copyright (C) 2024 Bryce Thuilot
# GPL-3.0 License
#
# booker.rb - A script to book a reservation on Resy
# Usage: ruby booker.rb --book-time "2024-01-01 12:00:00" --date "2024-01-01" --venue-url "https://resy.com/venue" --party-size 2
# Command Line Options:
#   --book_time: The time to book the reservation
#   --date: The date of the reservation
#   --venue_url: The URL of the venue
#   --party_size: The size of the party
#
# Environment Variables:
#   DRY_RUN: Enable dry run mode, does not book reservation
#   HEADLESS: Enable headless mode, does not open browser window
#   RESY_EMAIL: Resy login email
#   RESY_PASSWORD: Resy login password
#   QUIT_DRIVER: Quit the driver after booking, does not wait for user input


require 'time'
require 'uri'
require 'logger'
require 'optparse'
require 'selenium-webdriver'

#############
# Constants #
#############

# Home page of resy
HOME = "http://resy.com"
# Time to wait between actions
SLEEP_TIME = 0.5

##########
# Config #
##########

# enable Dry run mode
DRY_RUN = ENV['DRY_RUN']
# Headless mode
HEADLESS = ENV['HEADLESS']
# Resy login credentials
EMAIL = ENV['RESY_EMAIL']
PASSWORD = ENV['RESY_PASSWORD']
# Quit driver after booking
QUIT_DRIVER = ENV['QUIT_DRIVER']

$logger = Logger.new(STDOUT)
$logger.level = Logger::DEBUG


def main
  # Parse command line arguments
  options = parse_args
  # Parse venue link to a URI object
  venue_url = URI.parse(options[:venue_url])
  venue_url.query = nil # remove query params from venue url

  # parse book time to a Time object
  book_time = Time.parse(options[:book_time])
  # parse date to a Time object
  date = Time.parse(options[:date])
  # parse party size to an integer
  party_size = Integer(options[:party_size])

  puts "starting web driver"
  driver = get_driver

  puts "logging in"
  login(driver, date, party_size)
  
  wait_until(book_time)

  puts "beginning reservation booking for venue: #{venue_url}"
  book_reservation(driver, venue_url.to_s, date, party_size)

  if not QUIT_DRIVER
    puts "press enter to quit"
    gets
  end
  
  driver.quit

  puts "reservation complete"
end

# Waits for SLEEP_TIME seconds
def wait
  sleep SLEEP_TIME
end

# Waits until the given time
def wait_until(time)
  $logger.info("waiting until #{time}")
  diff = time - Time.now
  if diff > 0
    sleep diff
  end
end


# Parses command line arguments
# Returns a hash of options
def parse_args
  $logger.info("parsing command line arguments")
  options = {}
  OptionParser.new do |opt|
    opt.on('--book-time BOOKTIME') { |o| options[:book_time] = o }
    opt.on('--date DATE') { |o| options[:date] = o }
    opt.on('--venue-url VENUEURL') { |o| options[:venue_url] = o }
    opt.on('--party-size PARTYSIZE') { |o| options[:party_size] = o }
  end.parse!

  $logger.debug("options: #{options}")
  required_options = [:book_time, :date, :venue_url, :party_size]
  required_options.each do |opt|
    raise OptionParser::MissingArgument, "missing required option: #{opt}" if options[opt].nil?
  end

  $logger.info("command line arguments parsed")
  return options
end

# Returns a Selenium web driver
def get_driver
  options = Selenium::WebDriver::Chrome::Options.new
  if HEADLESS
    options.add_argument('--headless')
  end

  return Selenium::WebDriver.for :chrome, options: options
end

# Logs in to Resy
def login(driver, date, party_size)
  $logger.info("logging in")
  query = "date=#{date.strftime("%Y-%m-%d")}&seats=#{party_size}"
  driver.navigate.to "#{HOME}?#{query}"
  
  driver.find_element(:xpath, '//button[normalize-space(text())="Log in"]').click
  wait
  driver.find_element(:xpath, '//div[@class="AuthView__Footer"]/button').click
  wait

  $logger.debug("filling out login form")
  driver.find_element(:xpath, '//input[@name="email"]')
    .send_keys(EMAIL)
  driver.find_element(:xpath, '//input[@name="password"]')
    .send_keys(PASSWORD)
  driver.find_element(:xpath, '//form[@name="login_form"]').submit
  $logger.info("logged in")
end


# Books a reservation
def book_reservation(driver, venue_url, date, party_size)
  $logger.info("booking reservation")
  query = "date=#{date.strftime("%Y-%m-%d")}&seats=#{party_size}"
  driver.navigate.to "#{venue_url}?#{query}"
  wait

  if DRY_RUN
    $logger.info("dry run, not booking slot")
    puts "dry run, not booking slot"
    return
  end

  count = 0
  loop do 
    slots = driver.find_elements(:xpath, '//button[contains(@class, "ReservationButton")]')
    
    booked = false
    slots.each do |slot|
      if slot.text == "Notify"
        next
      end
      
      begin
        time = slot.find_element(:class, 'ReservationButton__time').text
        $logger.info("slot available at #{time}, booking slot...")
        slot.click
        wait
        $logger.debug("switching to iframe")
        iframe = driver.find_element(:xpath, '//iframe[@title="Resy - Book Now"]')
        driver.switch_to.frame(iframe)
        wait
        $logger.debug("confirming")
        driver.find_element(:xpath, '//div[@class="SummaryPage__book"]/button').click
        wait
        booked = true
        $logger.info("slot booked")
        break
      rescue => e
        $logger.error("error booking slot: #{e}")
        next
      end
    end
    break if booked || count > 10
    count += 1
    wait
  end
end


if __FILE__ == $0
  main
end


