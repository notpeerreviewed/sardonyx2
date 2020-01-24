
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

incidents <- dbGetQuery(con, "SELECT * FROM Incidents")
police_districts <- dbGetQuery(con, "SELECT Id, Name FROM PoliceDistricts")
police_nz_assets <- dbGetQuery(con, "SELECT IncidentId, PoliceAssetId, TotalHours, TotalCost FROM IncidentNzPoliceAssets")
police_assets <- dbGetQuery(con, "SELECT Id, Name, Cost FROM PoliceAssets")

# basic file for overview page
df <- incidents %>%
  select(IncidentEnvironmentId, SarCategoryOrNonSarActivityTypeId, ResponseId, NotificationDateTimeUtc,
         LocationFindLocationLatitude, LocationFindLocationLongitude, LocationIppOrLkpLatitude,
         LocationIppOrLkpLongitude, LivesSaved, LivesRescued, LivesAssisted, NumberPerishedOrAssumedPerished) %>%
  mutate(date = as.Date(NotificationDateTimeUtc) %>% as.character(),
         Environment = case_when(IncidentEnvironmentId == 1 ~ "Air",
                                 IncidentEnvironmentId == 2 ~ "Land",
                                 IncidentEnvironmentId == 3 ~ "Marine",
                                 TRUE ~ "Undetermined"),
         SarCategory = case_when(SarCategoryOrNonSarActivityTypeId == 1 ~ "Cat1",
                                 TRUE ~ "Cat2"),
         Response = case_when(ResponseId == 1 ~ "Communications",
                              ResponseId == 2 ~ "SAROP",
                              TRUE ~ "Other"),
         LocationFindLocationLatitude = case_when(is.na(LocationFindLocationLatitude) ~ LocationIppOrLkpLatitude,
                                                  TRUE ~ LocationFindLocationLatitude),
         LocationFindLocationLongitude = case_when(is.na(LocationFindLocationLongitude) ~ LocationIppOrLkpLongitude,
                                                  TRUE ~ LocationFindLocationLongitude)) %>%
  # filter(year(date) == 2019) %>%
  # filter(year(date) == 2019, is.na(LocationFindLocationLongitude)) %>%
  select(-NotificationDateTimeUtc, -IncidentEnvironmentId, -SarCategoryOrNonSarActivityTypeId, -ResponseId,
         -LocationIppOrLkpLatitude, -LocationIppOrLkpLongitude) %>%
  filter(!is.na(LocationFindLocationLongitude) & !is.na(LocationFindLocationLatitude & !is.na(date))) %>%
  mutate_at(vars(LivesSaved, LivesRescued, LivesAssisted, NumberPerishedOrAssumedPerished), ~ ifelse(is.na(.), 0, .))

# still need to manually reformat date to Y-m-d in the csv for some reason
write.csv(df, file = "data/sardonyx_data.csv", row.names = F)

##############################################################################################
##############################################################################################

# beacons data
beacon_country_codes <- dbGetQuery(con, "SELECT * FROM BeaconCountryCodes")
beacon_reasons_for_activation <- dbGetQuery(con, "SELECT * FROM BeaconReasonsForActivation")
beacon_type <- dbGetQuery(con, "SELECT * FROM BeaconTypes")


beacons <- incidents %>%
  select(IncidentEnvironmentId, contains("Beacon"), SarCategoryOrNonSarActivityTypeId,
         NotificationDateTimeUtc, LocationFindLocationLatitude, LocationFindLocationLongitude) %>%
  mutate(date = as.Date(NotificationDateTimeUtc) %>% as.character(),
         Environment = case_when(IncidentEnvironmentId == 1 ~ "Air",
                                 IncidentEnvironmentId == 2 ~ "Land",
                                 IncidentEnvironmentId == 3 ~ "Marine",
                                 TRUE ~ "Undetermined"),
         SarCategory = case_when(SarCategoryOrNonSarActivityTypeId == 1 ~ "Cat1",
                                 TRUE ~ "Cat2")) %>%
  filter(!is.na(LocationFindLocationLongitude) & !is.na(LocationFindLocationLatitude & !is.na(date))) %>%
  select(-IncidentEnvironmentId, -SarCategoryOrNonSarActivityTypeId, -NotificationDateTimeUtc) %>%
  left_join(beacon_country_codes[,c("Id", "Name")], by = c("BeaconCountryCodeId" = "Id")) %>%
  rename(CountryName = Name) %>%
  left_join(beacon_reasons_for_activation[,c("Id", "Name")], by = c("BeaconReasonForActivationId" = "Id")) %>%
  rename(ActivationReason = Name) %>%
  left_join(beacon_type[, c("Id", "Name")], by = c("BeaconTypeId" = "Id")) %>%
  rename(BeaconType = Name) %>%
  select(-BeaconCountryCodeId, -BeaconReasonForActivationId, -BeaconTypeId) %>%
  replace(is.na(.), "Unknown")

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
  st_set_geometry(NULL)


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
incidents <- dbGetQuery(con, "SELECT * FROM Incidents")
sar_category <- dbGetQuery(con, "SELECT Id, Name FROM SarCategoryOrNonSarActivityTypes")
responses <- dbGetQuery(con, "SELECT Id, Name FROM Responses")
activities_water <- dbGetQuery(con, "SELECT Id, Name FROM ActivitiesWater")
alert_method <- dbGetQuery(con, "SELECT Id, Name FROM AlertMethods")
causes_of_incident_vessel <- dbGetQuery(con, "SELECT Id, Name FROM CausesOfIncidentVessel")
root_cause <- dbGetQuery(con, "SELECT Id, Name FROM RootCauses")

subject_vessels <- dbGetQuery(con, "SELECT * FROM IncidentSubjectVessels")
non_recreational_vessel_types <- dbGetQuery(con, "SELECT Id, Name FROM NonRecreationalVesselTypes")
recreational_vessel_types <- dbGetQuery(con, "SELECT Id, Name FROM RecreationalVesselTypes")
vessel_master_profiles <- dbGetQuery(con, "SELECT Id, Name FROM VesselMasterProfiles")

# probably best to create a dedicated subjects page
subject_people <- dbGetQuery(con, "SELECT Id, IncidentId, Age, SexId, EthnicityId FROM IncidentSubjectPeople")
ethnicities <- dbGetQuery(con, "SELECT Id, Name FROM Ethnicities")

# we need to extract the data we require from the incidents table and then augment with the data from
# associated tables
df <- incidents %>%
  # select(Id, Deleted, IncidentEnvironmentId, BeaconActivation, BeaconTypeId, NotificationDateTimeUtc,
  #        CompletionDateTimeUtc, ResponseId, AlertMethodId, PoliceDistrictId, SarCategoryOrNonSarActivityTypeId,
  #        ActivityWaterId, CauseOfIncidentVesselId, LocationFindLocationLatitude, LocationFindLocationLongitude,
  #        RootCauseId,LivesSaved:FatalityAfterSarAlertedId) %>%
  select(Id, Deleted, IncidentEnvironmentId, NotificationDateTimeUtc,
         ActivityWaterId, CauseOfIncidentVesselId, LocationFindLocationLatitude, LocationFindLocationLongitude,
         RootCauseId) %>%
  filter(IncidentEnvironmentId == 3, Deleted != TRUE) %>%
  left_join(subject_vessels[,c("IncidentId", "RecreationalVesselTypeId", "NonRecreationalVesselTypeId")], by = c("Id" = "IncidentId")) %>%
  left_join(recreational_vessel_types, by = c("RecreationalVesselTypeId" = "Id")) %>%
  rename(RecVessel = Name) %>%
  left_join(non_recreational_vessel_types, by = c("NonRecreationalVesselTypeId" = "Id")) %>%
  rename(NonRecVessel = Name)




  left_join(activities_water, by = c("ActivityWaterId" = "Id")) %>%
  rename(WaterActivity = Name) %>%
  # left_join(alert_method, by = c("AlertMethodId" = "Id")) %>%
  # rename(AlertMethod = Name) %>%
  left_join(causes_of_incident_vessel, by = c("CauseOfIncidentVesselId" = "Id")) %>%
  rename(CauseOfIncident = Name) %>%
  left_join(root_cause, by = c("RootCauseId" = "Id")) %>%
  rename(RootCause = Name) %>%
  left_join(subject_vessels, by = c("Id" = "IncidentId"))
  
  
test <- df %>%
  filter(IncidentEnvironmentId == 3) %>%
  select(NotificationDateTimeUtc, WaterActivity) %>%
  mutate(date = as.Date(NotificationDateTimeUtc) %>% floor_date(unit = 'month')) %>%
  group_by(date) %>%
  count(WaterActivity) %>%
  ungroup() %>%
  filter(date > ymd("2019-05-06"))


ggplot(test, aes(x = date, y = n)) + geom_line() + facet_wrap(~WaterActivity)





incidents <- dbGetQuery(con, "SELECT * FROM DenormalizedIncidents")
vessels <- dbGetQuery(con, "SELECT * FROM DenormalizedSubjectVessels")

# db <- odbcConnect("nzsar")
# # test <- sqlTables(db)
# 
# # get the old police event records
# sql="SELECT * FROM Landing.Vessel"
# landing_vessel <- sqlQuery(db,sql)
# 
# df2 <- landing_vessel %>% distinct()
# 
# unique(df2$SelfPropelled)

# 
# # get the assets used in the old records
# sql="SELECT EventID, RecordType, AdminHrs, AdminCost FROM Staging.vwStaging_Admin"
# police_assets_old <- sqlQuery(db,sql)
# 
# police_assets_old_reduced <- police_assets_old %>%
#   filter(RecordType != "Total") %>%
#   left_join(police_incidents_old, by = "EventID") %>%
#   mutate(Event = toupper(Event)) %>%
#   filter(!is.na(Event))
# 
# # now join the old police records to the new SARdonyx records
# # using Police Event number as the key
# full_records <- police_spatial %>%
#   mutate(PoliceEventNumber = toupper(PoliceEventNumber)) %>%
#   left_join(police_assets_old_reduced, by = c("PoliceEventNumber" = "Event")) %>%
#   mutate(RecordType = case_when(is.na(RecordType) ~ AssetName,
#                                 RecordType == "Police heli" & AssetName == "Police Eagle Helicopter" ~ "Police Eagle Helicopter",
#                                 TRUE ~ RecordType),
#          AdminHrs = case_when(is.na(AdminHrs) ~ TotalHours,
#                               TRUE ~ AdminHrs),
#          AdminCost = case_when(RecordType == "Police Eagle Helicopter" ~ Cost,
#                                RecordType == "Other" ~ 0,
#                                is.na(AdminCost) ~ Cost,
#                                TRUE ~ AdminCost)) %>%
#   select(-EventID, -PoliceAssetId, -TotalHours, -Cost) %>%
#   distinct() %>%
#   mutate(TotalCost = AdminCost) %>%
#   select(-Id:-PoliceDistrictId) 


httw()
