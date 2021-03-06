require 'io/console'

require_relative '../config'

# The purpose of this script is to remove old versions of repositories on docker registries with the latest tag.
# When you push a new latest, the last latest is untagged and takes up diskspace.

registry_host = ENV.fetch('REGISTRY_HOST')

# Get array of repos
auth = {
  username: ENV.fetch('USERNAME'),
  password: ENV.fetch('PASSWORD')
}

repos_array = HTTParty.get("https://#{registry_host}/v2/_catalog", basic_auth: auth, verify: false).parsed_response["repositories"]
repos = repos_array.to_s.gsub(/\[|\]/, "").gsub(/"/, "")

puts ""
puts "We will clean all untagged images"
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

# Begin sanitizing the data by pulling out only lines with specified repo name
repo_stdin_array = []

array.each do |line|
  repos_array.each do |repo_name|
    if line.include?("#{repo_name}: marking manifest")
      repo_stdin_array << [repo_name, line]
    end
  end
end

# Pull out only the SHA's of images
repo_name_sha_array = []
repo_stdin_array.each do |repo_name, manifest|
  sha = manifest.split("manifest ").last
  repo_name_sha_array << [repo_name, sha]
end

puts ""
puts "These are the SHAs of every #{repos} image on the registry"
puts ""
puts repo_name_sha_array
puts ""

# Find the SHA for the image currently labeled as tags. We want to keep this images
tags_keep_sha_array = []
repos_array.each do |repo_name|
  %w(
    latest
    master
    development
  ).each do |tag|
    tags_keep_sha_array << HTTParty.get("https://#{registry_host}/v2/#{repo_name}/manifests/#{tag}", basic_auth: auth, verify: false, headers: {"Accept" => "application/vnd.docker.distribution.manifest.v2+json"}).headers["docker-content-digest"]
  end
end
# remove nil
tags_keep_sha_array = tags_keep_sha_array.compact

# Remove array with latest SHA from the array of report_names and SHA's
tags_keep_sha_array.each do |latest_sha|
  repo_name_sha_array.each do |repo_sha|
    repo_name_sha_array.delete(repo_sha) if repo_sha.include?(latest_sha)
  end
end

puts ""
puts "This is the list of SHAs of images to be deleted:"
puts repo_name_sha_array
puts ""
puts "We'll now use the v2 Docker Registry API to mark these images for deletion"
puts ""

# Mark images for deletion
repo_name_sha_array.each do |repo_name, sha|
  response = HTTParty.delete("https://#{registry_host}/v2/#{repo_name}/manifests/#{sha}", basic_auth: auth, verify: false)

  if response.code == 202
    puts "#{repo_name}: #{sha} marked for deletion"
  else
    puts "something wrong for #{repo_name}, response: #{response.code}"
  end
end

puts ""
puts "The SHA's (and their associated blobs) are now marked for deletion"
# Garbage Collection runs via cron at 4am
# puts "Garbage Collection is scheduled to run tomorrow at 4am"
