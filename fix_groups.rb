require 'xcodeproj'
project_path = 'AIFitnessCoach.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Find the main app group
app_group = project.main_group.groups.find { |g| g.name == 'AIFitnessCoach' }
if app_group
  services_group = app_group.groups.find { |g| g.name == 'Services' }
  if services_group
    puts "Services group found. Current path: #{services_group.path.inspect}"
    services_group.path = 'Services'
    puts "Services group path updated."
  end
end

# Find the test group
test_group = project.main_group.groups.find { |g| g.name == 'AIFitnessCoachTests' }
if test_group
  mocks_group = test_group.groups.find { |g| g.name == 'Mocks' }
  if mocks_group
    puts "Mocks group found. Current path: #{mocks_group.path.inspect}"
    mocks_group.path = 'Mocks'
    puts "Mocks group path updated."
  end
end

project.save
puts "Project saved."
