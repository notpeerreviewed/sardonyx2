
# script to clean data for use in dashboards

library(odbc)
library(magrittr)
library(dplyr)
library(tidyr)
library(stringr)
library(purrr)
library(lubridate)
library(sf)
library(ggplot2)
library(RODBC)
library(servr)

options(stringsAsFactors = F)

setwd("C:/Users/leanj/sardonyx_dashboard_v2")

con <- DBI::dbConnect(odbc::odbc(),
                      Server = "13.73.109.251",
                      Database = "sardonyxproduction-backup",
                      Driver = "SQL Server",
                      UID = "jeff@sardonyxqa.database.windows.net",
                      PWD = "Welc0m3S@rdonyx",
                      Port = 1433)

incidents <- dbGetQuery(con, "SELECT * FROM DenormalizedIncidents")
police_districts <- dbGetQuery(con, "SELECT Id, Name FROM PoliceDistricts")
police_nz_assets <- dbGetQuery(con, "SELECT IncidentId, PoliceAssetId, TotalHours, TotalCost FROM IncidentNzPoliceAssets")
police_assets <- dbGetQuery(con, "SELECT Id, Name, Cost FROM PoliceAssets")

# need to clean this up to account for the fact we are now using the Denormalised Incident table
# we may still need to use the old incident table occasionally for the legacy data column

# basic file for overview page
# df <- incidents %>%
#   select(IncidentEnvironmentId, SarCategoryOrNonSarActivityTypeId, ResponseId, NotificationDateTimeUtc,
#          LocationFindLocationLatitude, LocationFindLocationLongitude, LocationIppOrLkpLatitude,
#          LocationIppOrLkpLongitude, LivesSaved, LivesRescued, LivesAssisted, NumberPerishedOrAssumedPerished) %>%
#   mutate(date = as.Date(NotificationDateTimeUtc) %>% as.character(),
#          Environment = case_when(IncidentEnvironmentId == 1 ~ "Air",
#                                  IncidentEnvironmentId == 2 ~ "Land",
#                                  IncidentEnvironmentId == 3 ~ "Marine",
#                                  TRUE ~ "Undetermined"),
#          SarCategory = case_when(SarCategoryOrNonSarActivityTypeId == 1 ~ "Cat1",
#                                  TRUE ~ "Cat2"),
#          Response = case_when(ResponseId == 1 ~ "Communications",
#                               ResponseId == 2 ~ "SAROP",
#                               TRUE ~ "Other"),
#          LocationFindLocationLatitude = case_when(is.na(LocationFindLocationLatitude) ~ LocationIppOrLkpLatitude,
#                                                   TRUE ~ LocationFindLocationLatitude),
#          LocationFindLocationLongitude = case_when(is.na(LocationFindLocationLongitude) ~ LocationIppOrLkpLongitude,
#                                                   TRUE ~ LocationFindLocationLongitude)) %>%
#   # filter(year(date) == 2019) %>%
#   # filter(year(date) == 2019, is.na(LocationFindLocationLongitude)) %>%
#   select(-NotificationDateTimeUtc, -IncidentEnvironmentId, -SarCategoryOrNonSarActivityTypeId, -ResponseId,
#          -LocationIppOrLkpLatitude, -LocationIppOrLkpLongitude) %>%
#   filter(!is.na(LocationFindLocationLongitude) & !is.na(LocationFindLocationLatitude & !is.na(date))) %>%
#   mutate_at(vars(LivesSaved, LivesRescued, LivesAssisted, NumberPerishedOrAssumedPerished), ~ ifelse(is.na(.), 0, .))

# still need to manually reformat date to Y-m-d in the csv for some reason
write.csv(df, file = "data/sardonyx_data.csv", row.names = F)

##############################################################################################
##############################################################################################



beacons <- incidents %>%
  select(IncidentEnvironmentName, contains("Beacon"), SarCategoryOrNonSarActivityTypeName,
         NotificationDateTimeUtc, LocationFindLocationLatitude, LocationFindLocationLongitude, LocationIppOrLkpLatitude, LocationIppOrLkpLongitude) %>%
  filter(!is.na(BeaconTypeName)) %>%
  mutate(date = as.Date(NotificationDateTimeUtc) %>% floor_date(unit = 'month'),
         LocationFindLocationLatitude = case_when(is.na(LocationFindLocationLatitude) ~ LocationIppOrLkpLatitude,
                                                  TRUE ~ LocationFindLocationLatitude),
         LocationFindLocationLongitude = case_when(is.na(LocationFindLocationLongitude) ~ LocationIppOrLkpLongitude,
                                                   TRUE ~ LocationFindLocationLongitude)) %>%
  filter(!is.na(LocationFindLocationLongitude) & !is.na(LocationFindLocationLatitude & !is.na(date)))

# load the regions shapefile
regional_councils <- st_read("H:/data/regional-councils/nz-regional-councils-2012-yearly-pattern.shp")

beacons_by_district <- beacons %>%
  filter(!is.na(LocationFindLocationLatitude),
         !is.na(LocationFindLocationLongitude)) %>%
  st_as_sf(coords = c("LocationFindLocationLongitude", "LocationFindLocationLatitude"), remove = F) %>%
  st_set_crs(4326) %>%
  st_join(regional_councils["NAME"]) %>%
  mutate(NAME = case_when(is.na(NAME) ~ "Unknown",
                          TRUE ~ NAME)) %>%
  st_set_geometry(NULL) %>%
  select(IncidentEnvironmentName, BeaconReasonForActivationName, BeaconTypeName, SarCategoryOrNonSarActivityTypeName,
         LocationFindLocationLatitude, LocationFindLocationLongitude, date, NAME) %>%
  mutate(Region = str_replace_all(NAME, " Region", "")) %>%
  select(-NAME)

colnames(beacons_by_district) <- c("Environment", "Activation", "Type", "SarCategory", "Lat", "Long", "date", "Region")


write.csv(beacons_by_district, file = "data/beacons_data.csv", row.names = F)

##############################################################################################
##############################################################################################

# Police Data
#police_districts_spatial <- st_read("H:/data/police_district_boundaries/nz-police-district-boundaries.shp")
police_areas_spatial <- st_read("H:/data/police_area_boundaries/nz-police-area-boundaries.shp")


incidents_history <- dbGetQuery(con, "SELECT * FROM IncidentsHistory")

# calculate the lag in reporting
lag <- incidents_history %>%
  filter(!is.na(PoliceEventNumber)) %>%
  mutate(CompletionDateTimeUtc = case_when(is.na(CompletionDateTimeUtc) & !is.na(NotificationDateTimeUtc) ~ NotificationDateTimeUtc,
                                           is.na(CompletionDateTimeUtc) & !is.na(DistressSituationDateTimeUtc) ~ DistressSituationDateTimeUtc,
                                           TRUE ~ CompletionDateTimeUtc)) %>%
  group_by(PoliceEventNumber) %>%
  mutate(incident_end = max(CompletionDateTimeUtc),
         report_complete = max(SysEndTime)) %>%
  ungroup() %>%
  filter(CompletionDateTimeUtc %>% as.Date() %>% ymd() > "2019-05-03") %>%
  select(PoliceEventNumber, NotificationDateTimeUtc, CompletionDateTimeUtc, SysStartTime, SysEndTime, incident_end, report_complete) %>%
  mutate(duration = difftime(report_complete, incident_end, units = "days") %>% as.numeric()) %>%
  select(PoliceEventNumber, duration) %>%
  distinct() %>%
  filter(!is.na(duration) & duration > 0) %>%
  mutate(duration = format(duration, scientific = FALSE) %>% as.numeric() %>% round(2)) %>%
  rename(reporting_lag_days = duration)
  


police_spatial <- incidents %>%
  filter(!is.na(PoliceEventNumber) | !Deleted, SarCategoryOrNonSarActivityTypeId %in% c(1,2)) %>%
  left_join(police_districts[,c("Id", "Name")], by = c("PoliceDistrictId" = "Id")) %>%
  rename(District = Name) %>%
  replace_na(list(LocationFindLocationLatitude = 0,
                  LocationFindLocationLongitude = 0)) %>%
  st_as_sf(coords = c("LocationFindLocationLongitude", "LocationFindLocationLatitude"), remove = F) %>%
  st_set_crs(4326) %>%
  st_join(police_areas_spatial[,c("AREA_NAME", "DISTRICT_N", "geometry")]) %>%
  mutate(date = floor_date(as.Date(NotificationDateTimeUtc), unit = 'month'),
         Area = case_when(is.na(AREA_NAME) ~ "Unknown",
                          TRUE ~ AREA_NAME)) %>%
  st_set_geometry(NULL) %>%
  select(-AREA_NAME, -DISTRICT_N) %>%
  left_join(lag, by = "PoliceEventNumber") %>%
  mutate(reporting_lag_days = case_when(is.na(reporting_lag_days) ~ 0,
                              TRUE ~ reporting_lag_days)) %>%
  mutate(Environment = case_when(IncidentEnvironmentId == 1 ~ "Air",
                                 IncidentEnvironmentId == 2 ~ "Land",
                                 IncidentEnvironmentId == 3 ~ "Marine",
                                 TRUE ~ "Undetermined"),
         SarCategory = case_when(SarCategoryOrNonSarActivityTypeId == 1 ~ "Cat1",
                                 TRUE ~ "Cat2"),
         Response = case_when(ResponseId == 1 ~ "Communications",
                              ResponseId == 2 ~ "SAROP",
                              TRUE ~ "Other"),
         Status = case_when(StatusId == 1 ~ "In Progress",
                            StatusId == 2 ~ "Awaiting Approval",
                              TRUE ~ "Closed")) %>%
  select(Id, date, Environment, SarCategory, Response, SarSquadId, PoliceEventNumber,
         LocationFindLocationLatitude, LocationFindLocationLongitude,
         Status, TotalHours, TotalPeople, District, Area, reporting_lag_days)
  
write.csv(police_spatial, file = "data/police_spatial.csv", row.names = F)

test <- police_spatial %>%
  filter(!is.na(District), reporting_lag_days > 0) %>%
  group_by(District) %>%
  count()

#ggplot(test, aes(x = District, y = reporting_lag_days)) + geom_boxplot() + coord_flip()



##############################################################################################
##############################################################################################

# Harbourmaster Dataset
incidents <- dbGetQuery(con, "SELECT * FROM DenormalizedIncidents")

legacy_incidents <- dbGetQuery(con, "SELECT * FROM Incidents")

subject_vessels <- dbGetQuery(con, "SELECT * FROM DenormalizedSubjectVessels")


# probably best to create a dedicated subjects page
subject_people <- dbGetQuery(con, "SELECT IncidentId, Age, SexName, EthnicityName FROM DenormalizedSubjectPeople")

# we need to extract the data we require from the incidents table and then augment with the data from
# associated tables
incidents <- incidents %>%
  select(IncidentId, Deleted, IncidentEnvironmentName, contains("Beacon"), NotificationDateTimeUtc, CompletionDateTimeUtc,
         ResponseName, AlertMethodName, ActivityWaterName, CauseOfIncidentVesselName, contains("Latitude"), contains("Longitude"),
         RootCauseName, LivesSaved, LivesRescued, LivesAssisted, NumberInParty, NumberPerishedOrAssumedPerished) %>%
  filter(IncidentEnvironmentName == "Water", Deleted != TRUE) %>%
  left_join(subject_vessels[,c("IncidentId", "RecreationalVesselTypeName", "NonRecreationalVesselTypeName")], by = "IncidentId") 


# now we need to extract the legacy boating informatin from the historical records
# and map it to the new categories as closely as possible

# function to clean the legacy data column
clean_legacy_data <- function(data){
  df <- data %>%
    str_replace_all("\\{|\\}|\"", '') %>% 
    str_split(', ') %>% 
    unlist() %>% 
    as.data.frame() %>% 
    separate(., col = ., into = c("key", "value"), sep = ": ") %>%
    filter(value != "") %>%
    distinct(key, .keep_all = T)
  
  return(df)
}

  
temp <- legacy_incidents %>%
  filter(str_detect(LegacyData, "Vessel")) %>%
  mutate(LegacyClean = map(LegacyData, clean_legacy_data)) %>%
  select(Id, LegacyClean)

vessels <- data.frame()

for(i in 1:nrow(temp)){
  df <- temp[i,2][[1]] %>%
    spread(key, value) %>%
    mutate(Id = temp[i, "Id"])
  
  vessels <- bind_rows(vessels, df)
} 


motors <- c("Outboard", "Single main engine", "Surface Drive", "Jet", "Shafts", "Twin Outboards",  "Twin main engines", "Airboat")

vessel_classifications <- vessels %>%
  select(Id, Powered, PropulsionType, VesselOwnership, VesselSize, Sailer, SelfPropelled) %>%
  mutate(NonRecreationalBoating = case_when(VesselOwnership == "Commercial fishing" ~ "Fishing/Trawling Vessel",
                                            VesselOwnership == "Military" ~ "NZDF Vessel",
                                            VesselOwnership == "Shipping" ~ "Cargo/Container Vessel",
                                            VesselOwnership == "Charter" ~ "Passenger Vessel",
                                            !VesselOwnership %in% c("Private", "Unknown", NA) ~ "Other Commercial Vessel"),
         RecreationalBoating = case_when(Powered == "PWC/Jet Ski" ~ "Jetski",
                                         str_detect(SelfPropelled, "Kayak") ~ "Kayak",
                                         Powered == "Motor sailer" & VesselSize %in% c("0-3", "3-5") ~ "Sailboat less than or equal to 6m",
                                         Powered == "Motor sailer" & !VesselSize %in% c("0-3", "3-5") ~ "Sailboat over 6m",
                                         Powered %in% c("Runabout", "Launch", "Power vessel RHIB") & 
                                           VesselSize %in% c("0-3", "3-5") ~ "Power Boat less than or equal to 6m",
                                         Powered %in% c("Runabout", "Launch", "Power vessel RHIB") & 
                                           !VesselSize %in% c("0-3", "3-5") ~ "Power Boat over 6m",
                                         Powered %in% c("Other", NA) & 
                                           PropulsionType %in% motors &
                                           VesselSize %in% c("0-3", "3-5") ~ "Power Boat less than or equal to 6m",
                                         Powered %in% c("Other", NA) & 
                                           PropulsionType %in% motors &
                                           !VesselSize %in% c("0-3", "3-5") ~ "Power Boat over 6m",
                                         SelfPropelled == "Rowing dinghy" | Sailer == "Sailing Dinghy" ~ "Dinghy",
                                         str_detect(Sailer, "Yacht") & 
                                           VesselSize %in% c("0-3", "3-5") ~ "Sailboat less than or equal to 6m",
                                         str_detect(Sailer, "Yacht") & 
                                           !VesselSize %in% c("0-3", "3-5") ~ "Sailboat over 6m",
                                         TRUE ~ "Other")) %>%
  mutate(RecreationalBoating = ifelse(!is.na(NonRecreationalBoating), NA, RecreationalBoating)) %>%
  select(Id, NonRecreationalBoating, RecreationalBoating)


test <- incidents %>%
  left_join(vessel_classifications, by = c("IncidentId" = "Id"))



##############################################################################################
##############################################################################################

incidents <- dbGetQuery(con, "SELECT * FROM DenormalizedIncidents")
resources <- dbGetQuery(con, "SELECT * FROM Resources")
assets <- dbGetQuery(con, "SELECT * FROM Assets")

police_areas_spatial <- st_read("H:/data/police_area_boundaries/nz-police-area-boundaries.shp")


resources_tidy <- resources %>%
  select(-contains("Unit"))

assets_tidy <- assets %>%
  select(-contains("Asset")) %>%
  rename(Asset_Source = Source,
         Asset_Name = Name,
         Asset_Hours = TotalHours,
         Asset_Cost = TotalCost)

df <- incidents %>%
  filter(!Deleted) %>%
  select(IncidentId, PoliceEventNumber, IncidentEnvironmentName, NotificationDateTimeUtc, CompletionDateTimeUtc,
         ResponseName, LocationIppOrLkpLatitude, LocationIppOrLkpLongitude,
         LocationFindLocationLatitude, LocationFindLocationLongitude, LivesSaved:LivesAssisted, NumberPerishedOrAssumedPerished) %>%
  mutate(NotificationDateTimeUtc = ymd_hms(NotificationDateTimeUtc),
         CompletionDateTimeUtc = ymd_hms(CompletionDateTimeUtc),
         Date = NotificationDateTimeUtc %>% floor_date(unit = 'month'),
         Duration = difftime(CompletionDateTimeUtc, NotificationDateTimeUtc, units = "hours", signif(., 3)) %>% as.numeric(),
         LocationFindLocationLatitude = case_when(is.na(LocationFindLocationLatitude) ~ LocationIppOrLkpLatitude,
                                                  TRUE ~ LocationFindLocationLatitude),
         LocationFindLocationLongitude = case_when(is.na(LocationFindLocationLongitude) ~ LocationIppOrLkpLongitude,
                                                   TRUE ~ LocationFindLocationLongitude)) %>%
  select(-LocationIppOrLkpLatitude, -LocationIppOrLkpLongitude) %>%
  replace_na(list(LocationFindLocationLatitude = 0,
                  LocationFindLocationLongitude = 0)) %>%
  filter(ResponseName == "SAROP conducted", !is.na(PoliceEventNumber), abs(LocationFindLocationLatitude) < 90) %>%
  left_join(resources_tidy, by = "IncidentId") %>%
  left_join(assets_tidy, by = "IncidentId") %>%
  st_as_sf(coords = c("LocationFindLocationLongitude", "LocationFindLocationLatitude"), remove = F) %>%
  st_set_crs(4326) %>%
  st_join(police_areas_spatial[,c("AREA_NAME", "DISTRICT_N", "geometry")]) %>%
  mutate(Duration = case_when(Duration < 0 ~ 0,
                              TRUE ~ Duration))


write.csv(df, file = "data/police_resources.csv", row.names = F)



# ggplot(df, aes(x = Duration)) +
#   geom_density() +
#   scale_x_continuous(trans = "log10", labels = scales::comma_format(accuracy = 0.01))






httw()
