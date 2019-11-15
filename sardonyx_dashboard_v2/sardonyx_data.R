
# script to clean data for use in dashboards

library(odbc)
library(magrittr)
library(dplyr)
library(tidyr)
library(lubridate)
library(sf)
library(ggplot2)
library(RODBC)
library(servr)

setwd("C:/Users/leanj/sardonyx_dashboard_v2")

# basic file for overview page
df <- incidents %>%
  select(IncidentEnvironmentId, SarCategoryOrNonSarActivityTypeId, ResponseId, NotificationDateTimeUtc,
         LocationFindLocationLatitude, LocationFindLocationLongitude, LivesSaved, LivesRescued,
         LivesAssisted, NumberPerishedOrAssumedPerished) %>%
  mutate(date = as.Date(NotificationDateTimeUtc) %>% as.character(),
         Environment = case_when(IncidentEnvironmentId == 1 ~ "Air",
                                 IncidentEnvironmentId == 2 ~ "Land",
                                 IncidentEnvironmentId == 3 ~ "Marine",
                                 TRUE ~ "Undetermined"),
         SarCategory = case_when(SarCategoryOrNonSarActivityTypeId == 1 ~ "Cat1",
                                 TRUE ~ "Cat2"),
         Response = case_when(ResponseId == 1 ~ "Communications",
                              ResponseId == 2 ~ "SAROP",
                              TRUE ~ "Other")) %>%
  select(-NotificationDateTimeUtc, -IncidentEnvironmentId, -SarCategoryOrNonSarActivityTypeId, -ResponseId) %>%
  filter(!is.na(LocationFindLocationLongitude) & !is.na(LocationFindLocationLatitude & !is.na(date))) %>%
  mutate_at(vars(LivesSaved, LivesRescued, LivesAssisted, NumberPerishedOrAssumedPerished), ~ ifelse(is.na(.), 0, .))

# still need to manually reformat date to Y-m-d in the csv for some reason
write.csv(df, file = "data/sardonyx_data.csv", row.names = F)



# beacons data

beacons <- incidents %>%
  select(IncidentEnvironmentId, contains("Beacon"), SarCategoryOrNonSarActivityTypeId,
         NotificationDateTimeUtc, LocationFindLocationLatitude, LocationFindLocationLongitude)

# load the regions shapefile
regional_councils <- st_read("H:/data/regional-councils/nz-regional-councils-2012-yearly-pattern.shp")

beacons_by_district <- beacons %>%
  filter(!is.na(LocationFindLocationLatitude),
         !is.na(LocationFindLocationLongitude)) %>%
  st_as_sf(coords = c("LocationFindLocationLongitude", "LocationFindLocationLatitude")) %>%
  st_set_crs(4326) %>%
  st_join(regional_councils["NAME"]) %>%
  mutate(NAME = case_when(is.na(NAME) ~ "Unknown",
                          TRUE ~ NAME))


unique(beacons_by_district$NAME)


httw()