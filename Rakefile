require 'colorize'
require 'html-proofer'
require 'jekyll'

task :default => :test

desc 'Build the site with Jekyll'
task :build do
  Jekyll::Commands::Build.process(profile: true)
end

desc 'Remove generated site'
task :clean do
  Jekyll::Commands::Clean.process({})
end

desc 'Validate _site/ with html-proofer'
task :validate do
  HTMLProofer.check_directory('./_site', {
    :url_ignore => [
      /eurovision.tv/, # URL checks always 403 on this, I guess some kind of bot check
      /transtechsocial.org/, # regularly times out
    ],
    :check_html => true,
    :assume_extension => true,
    :internal_domains => ["https://daenney.github.io"],
    :directory_index_file => "index.html",
    :typhoeus => {
      :headers => { "User-Agent" => "Mozilla/5.0 (Windows NT 10.0; rv:68.0) Gecko/20100101 Firefox/68.0" }
    }
  }).run
end

desc 'Check for Jekyll deprecation issues'
task :doctor do
  Jekyll::Commands::Doctor.process({})
end

desc 'Build and validate the site'
task :test do
  notify 'Building site'
  Rake::Task['build'].invoke
  notify 'Validating site'
  Rake::Task['validate'].invoke
  if !ENV.key?("CI")
    notify 'Checking for deprecation issues'
    Rake::Task['doctor'].invoke
  end
end

def notify message
  puts
  puts '###################################################'.blue
  puts "#{message}...".blue
  puts '###################################################'.blue
  puts
  STDOUT.flush
end
