#!/usr/bin/env ruby

# Automated Xcode Project Setup for Turnbox macOS VPN Client
# This script will automatically create targets, add files, and configure settings

require 'xcodeproj'

puts "🔧 Automated Xcode Project Setup"
puts "================================="

# Configuration
APP_NAME = "Turnbox-macOS"
extension_name = "PacketTunnelExtension"
app_bundle_id = "org.turnbox.app.macos"
extension_bundle_id = "org.turnbox.app.macos.PacketTunnel"
app_group_id = "group.org.turnbox.app.shared"

project_path = "iosApp/iosApp.xcodeproj"

# Check if project exists
unless File.exist?(project_path)
  puts "❌ Error: Project not found at #{project_path}"
  puts "   Make sure you're running this from the project root"
  exit 1
end

# Load project
puts "📂 Loading project..."
project = Xcodeproj::Project.open(project_path)

# Create macOS App Target
puts "🎯 Creating macOS App target..."
app_target = project.new_target(:application, APP_NAME, :osx)
app_target.build_configurations.each do |config|
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = app_bundle_id
  config.build_settings['INFOPLIST_FILE'] = "macosApp/Info.plist"
  config.build_settings['CODE_SIGN_ENTITLEMENTS'] = "macosApp/macosApp.entitlements"
  config.build_settings['FRAMEWORK_SEARCH_PATHS'] = "$(inherited) $(PROJECT_DIR)/../sharedUI/build/bin/macosArm64/debugFramework"
  config.build_settings['LIBRARY_SEARCH_PATHS'] = "$(inherited)"
end

# Create Packet Tunnel Extension Target
puts "🎯 Creating Packet Tunnel Extension target..."
extension_target = project.new_target(:app_extension, extension_name, :osx)
extension_target.build_configurations.each do |config|
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = extension_bundle_id
  config.build_settings['INFOPLIST_FILE'] = "#{extension_name}/Info.plist"
  config.build_settings['CODE_SIGN_ENTITLEMENTS'] = "#{extension_name}/#{extension_name}.entitlements"
  config.build_settings['FRAMEWORK_SEARCH_PATHS'] = "$(inherited) $(PROJECT_DIR)/../sharedUI/build/bin/macosArm64/debugFramework"
end

# Add files to project
puts "📄 Adding source files..."

def add_file_to_project(project, path, target)
  file_reference = project.new_file(path)
  target.add_file_references([file_reference])
  puts "   ✅ Added: #{path}"
rescue => e
  puts "   ❌ Failed: #{path} - #{e.message}"
end

# Add main app files
app_files = [
  "macosApp/TurnboxApp.swift",
  "macosApp/MacosVpnManager.swift",
  "macosApp/ContentView.swift",
  "macosApp/MenuBarExtra.swift",
]

app_files.each { |file| add_file_to_project(project, file, app_target) }

# Add extension files
extension_files = [
  "#{extension_name}/#{extension_name}.swift",
]

extension_files.each { |file| add_file_to_project(project, file, extension_target) }

# Add entitlements and Info.plist files
project.new_file("macosApp/macosApp.entitlements")
project.new_file("macosApp/Info.plist")
project.new_file("#{extension_name}/#{extension_name}.entitlements")
project.new_file("#{extension_name}/Info.plist")

# Configure App Groups capability
puts "🔐 Configuring App Groups..."

# Add App Group
app_group_id

# Save project
puts "💾 Saving project..."
project.save

puts ""
puts "✅ Automated setup complete!"
puts ""
puts "Next steps:"
puts "1. Run: gem install xcodeproj (if you haven't already)"
puts "2. Run: ./automated-xcode-setup.rb"
puts "3. Open iosApp.xcodeproj and verify targets are created"
puts "4. Manually add SharedUI.framework to both targets in Xcode"
puts "5. Add native binaries to Resources folder"
