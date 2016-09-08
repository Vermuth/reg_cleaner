require 'io/console'
require 'httparty'
require 'byebug'

# The purpose of this script is to remove old versions of repositories on docker registries with the latest tag.
# When you push a new latest, the last latest is untagged and takes up diskspace.

# Set registry host
puts "enter the hostname of your docker registry"
registry_host = STDIN.gets.gsub( / *\n+/, "" )

# Get Auth for docker registry
puts "enter docker registry username"
username = STDIN.gets.gsub( / *\n+/, "" )
puts "enter docker registry password"
# Hide password output to terminal
password = STDIN.noecho(&:gets).gsub( / *\n+/, "" )
puts ""

# Get array of repos
auth = {:username => username, :password => password}
repos_array = HTTParty.get("https://#{registry_host}/v2/_catalog", :basic_auth => auth, :verify => false).parsed_response["repositories"]
repos = repos_array.to_s.gsub(/\[|\]/, "").gsub(/"/, "")

puts "Which repo would you like to clean on the docker registry? #{repos}"

# capture the selected repository name
repo_name = STDIN.gets.gsub( / *\n+/, "" )

# check that the repository is valid before progressing
if repos_array.include? repo_name
  puts ""
  puts "We will be cleaning up the #{repo_name} repo"
  puts ""
  puts "Please ssh to #{registry_host} and run the following command as root: "
  puts ""
  puts "docker exec -it <container ID or name> bin/registry garbage-collect --dry-run /etc/docker/registry/config.yml"
  puts ""
  puts "When you are done, paste the output here, and then type in all caps, END and hit return"
  puts "(When you paste, you will not be able to see your text in the terminal to keep things tidy; don't forget to type END)"
  $/ = "END"
  dry_run_output = STDIN.noecho(&:gets)
  array = dry_run_output.split("\n")
  $/ = "\n"

  # Begin santizing the data by pulling out only lines with specified repo name
  stdin_array = []
  array.each do |line|
    if line.include?("#{repo_name}: marking manifest")
      stdin_array << line
    end
  end

  # Pull out only the SHA's of images
  sha_array = []
  stdin_array.each do |manifest|
    sha = manifest.split("manifest ").last
    sha_array << sha
  end

  puts ""
  puts "These are the SHAs of every #{repo_name} image on the registry"
  puts ""
  puts sha_array
  puts ""

  # Find the SHA for the image currently labeled as latest. We want to keep this image
  @latest_sha = HTTParty.get("https://#{registry_host}/v2/#{repo_name}/manifests/latest", :basic_auth => auth, :verify => false, :headers => {"Accept" => "application/vnd.docker.distribution.manifest.v2+json"}).headers["docker-content-digest"]

  # Remove the latest SHA from the array of SHA's
  sha_array.delete(@latest_sha)
  puts ""
  puts "This is the list of SHAs of images to be deleted:"
  puts sha_array
  puts ""
  puts "We'll now use the v2 Docker Registry API to mark these images for deletion"
  puts ""

  # Mark images for deletion
  sha_array.each do |sha|
    response = HTTParty.delete("https://#{registry_host}/v2/#{repo_name}/manifests/#{sha}", :basic_auth => auth, :verify => false)
    if response.code == 202
      puts "#{sha} marked for deletion"
    else
      puts response.code
    end
  end
  puts ""
  puts "The SHA's (and their associated blobs) are now marked for deletion"
  # Garbage Collection runs via cron at 4am
  puts "Garbage Collection is scheduled to run tomorrow at 4am"
else
  puts "You didn't enter a valid repo"
end
