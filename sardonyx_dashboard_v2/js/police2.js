
const dateFormatSpecifier = '%Y-%m-%d';
const dateFormat = d3.timeFormat(dateFormatSpecifier);
const dateFormatParser = d3.timeParse(dateFormatSpecifier);

let districtSelector = dc.selectMenu("#district-selector");
let areaSelector = dc.selectMenu("#area-selector");
let environmentChart = dc.rowChart('#police-environment-rowchart');
let assetChart = dc.rowChart('#police-assets-rowchart');
let LivesSavedND = dc.numberDisplay("#LivesSaved"),
    LivesRescuedND = dc.numberDisplay("#LivesRescued"),
    LivesAssistedND = dc.numberDisplay("#LivesAssisted"),
    LivesLostND = dc.numberDisplay("#LivesLost"),
    AssetHoursND = dc.numberDisplay("#asset-total-hours"),
    AssetCostND = dc.numberDisplay("#asset-total-cost"),
    ResourceHoursND = dc.numberDisplay("#resource-total-hours"),
    ResourceCostND = dc.numberDisplay("#resource-total-cost"),
    ResourcePeopleND = dc.numberDisplay("#resource-total-people");
let monthlySeries = dc.lineChart('#police-incident-series');
let mapChart = dc_leaflet.markerChart("#map-chart");

monthlySeries.margins().left = 40;


d3.csv('data/police_resources.csv').then(function (data) {
  data.forEach(function (d) {
        d.lat = +d.LocationFindLocationLatitude;
        d.lon = +d.LocationFindLocationLongitude;
        d.date = dateFormatParser(d.Date);
        d.month = d3.timeMonth(d.date);
        d.geo = d.lat + "," + d.lon;
        d.LivesSaved = +d.LivesSaved;
        d.LivesRescued = +d.LivesRescued;
        d.LivesAssisted = +d.LivesAssisted;
        d.LivesLost = +d.NumberPerishedOrAssumedPerished;
        d.Duration = +d.Duration;
        d.Source = d.Source === "NA" ? null:d.Source;
        d.Name = d.Name === "NA" ? null:d.Name;
        d.Asset_Source = d.Asset_Source === "NA" ? null:d.Asset_Source;
        // d.Asset_Name = d.Asset_Name === "NA" ? null:d.Asset_Name;
        d.Asset_Name = d.Asset_Name;
        d.Asset_Cost = d.Asset_Cost === "NA" ? 0:+d.Asset_Cost;
        d.Asset_Hours = d.Asset_Hours === "NA" ? 0:+d.Asset_Hours;
        d.Total_Cost = d.Total_Cost === "NA" ? 0:+d.Total_Cost;
        d.Total_Hours = d.Total_Hours === "NA" ? 0:+d.Total_Hours;
        d.Total_People = d.Total_People === "NA" ? 0:+d.Total_People;
    });

  console.log(data);

  /* now we create the crossfilter and set up the dimensions and groups*/
  let ndx = crossfilter(data);
  let all = ndx.groupAll();

  /* create a dimension for monthly incidents */
  let districtDimension = ndx.dimension(function (d) {
        return d.DISTRICT_N;
    });

  let districtDimensionGroup = districtDimension.group();

  /* create a dimension for monthly incidents */
  let areaDimension = ndx.dimension(function (d) {
        return d.AREA_NAME;
    });

  let areaDimensionGroup = areaDimension.group();


  /* create a dimension for monthly incidents */
  let monthlyDimension = ndx.dimension(function (d) {
        return d.month;
    });

  let monthlyDimensionGroup = monthlyDimension.group();

  let metricsGroup = ndx.groupAll().reduce(
    function(p, v){
      ++p.count;
      p.LivesSaved += v.LivesSaved;
      p.LivesRescued += v.LivesRescued;
      p.LivesAssisted += v.LivesAssisted;
      p.LivesLost += v.LivesLost;
      p.Asset_Cost += v.Asset_Cost;
      p.Asset_Hours += v.Asset_Hours;
      p.Total_Cost += v.Total_Cost;
      p.Total_Hours += v.Total_Hours;
      p.Total_People += v.Total_People;
      return p;
    },
    function(p, v){
      --p.count;
      p.LivesSaved -= v.LivesSaved;
      p.LivesRescued -= v.LivesRescued;
      p.LivesAssisted -= v.LivesAssisted;
      p.LivesLost -= v.LivesLost;
      p.Asset_Cost -= v.Asset_Cost;
      p.Asset_Hours -= v.Asset_Hours;
      p.Total_Cost -= v.Total_Cost;
      p.Total_Hours -= v.Total_Hours;
      p.Total_People -= v.Total_People;
      return p;
    },
    function(){
      return{
        count: 0,
        LivesSaved: 0,
        LivesRescued: 0,
        LivesAssisted: 0,
        LivesLost: 0,
        Asset_Cost: 0,
        Asset_Hours: 0,
        Total_Cost: 0,
        Total_Hours: 0,
        Total_People: 0
      };

    }
  );

  // create region regionSelector
  districtSelector
    .dimension(districtDimension)
    .group(districtDimensionGroup);

  // create region regionSelector
  areaSelector
    .dimension(areaDimension)
    .group(areaDimensionGroup);


  /* create a dimension for Environment */
  let environmentDimension = ndx.dimension(function (d) {
        return d.IncidentEnvironmentName;
    });

  let environmentDimensionGroup = environmentDimension.group();
  console.log(environmentDimensionGroup.all())

  /* create a dimension for Environment */
  let assetDimension = ndx.dimension(function (d) {
        return d.Asset_Name;
    });

    function remove_bins(source_group) { //
      return {
        all: function() {

          return source_group.all().filter(function(d) {
            // console.log(d)
            return d.key != "NA" && d.value != 0;
          });
        }
      };
    }



  let assetDimensionGroup = remove_bins(assetDimension.group().reduceCount());
  // let assetDimensionGroup = assetDimension.group();
  console.log(assetDimensionGroup.all())

  /* create a dimension for map data */
  let mapDimension = ndx.dimension(function (d) {
        return d.geo;
    });

  let mapDimensionGroup = mapDimension.group().reduce(
          function(p, v) {
              p.IncidentEnvironmentName = v.IncidentEnvironmentName;
              ++p.count;
              return p;
          },
          function(p, v) {
              --p.count;
              return p;
          },
          function() {
              return {count: 0};
          }
      );


// create the numberDisplays for the key metrics
  LivesSavedND
    .formatNumber(d3.format(",.2r"))
    .valueAccessor(function(p){
      return p.LivesSaved;
    })
    .group(metricsGroup);

  LivesRescuedND
    .formatNumber(d3.format(",.2r"))
    .valueAccessor(function(p){
      return p.LivesRescued;
    })
    .group(metricsGroup);

  LivesAssistedND
    .formatNumber(d3.format(",.2r"))
    .valueAccessor(function(p){
      return p.LivesAssisted;
    })
    .group(metricsGroup);

  LivesLostND
    .formatNumber(d3.format(",.2r"))
    .valueAccessor(function(p){
      return p.LivesLost;
    })
    .group(metricsGroup);

  AssetHoursND
    .formatNumber(d3.format(",.2r"))
    .valueAccessor(function(p){
      return p.Asset_Hours;
    })
    .group(metricsGroup);

  AssetCostND
    .formatNumber(d3.format("$,.2r"))
    .valueAccessor(function(p){
      return p.Asset_Cost;
    })
    .group(metricsGroup);

  ResourceHoursND
    .formatNumber(d3.format(",.2r"))
    .valueAccessor(function(p){
    return p.Total_Hours;
    })
    .group(metricsGroup);

  ResourceCostND
    .formatNumber(d3.format("$,.2r"))
    .valueAccessor(function(p){
      return p.Total_Cost;
    })
    .group(metricsGroup);

  ResourcePeopleND
    .formatNumber(d3.format(",.2r"))
    .valueAccessor(function(p){
      return p.Total_People;
    })
    .group(metricsGroup);



  /* build row chart for Environments*/
  environmentChart
    .width(200)
    .height(150)
    .margins({top: 0, left: 10, right: 10, bottom: 20})
    .dimension(environmentDimension)
    .group(environmentDimensionGroup)
    .transitionDuration(500)
    .controlsUseVisibility(true)
    .elasticX(true)
    .xAxis()
    .ticks(3);


    assetChart
      // .width(300)
      .height(300)
      .margins({top: 0, left: 10, right: 10, bottom: 20})
      .dimension(assetDimension)
      .group(assetDimensionGroup)
      .transitionDuration(500)
      .controlsUseVisibility(true)
      .elasticX(true)
      .xAxis()
      .ticks(3);



  /* build line chart for time series*/
  monthlySeries
    .height(150)
    .dimension(monthlyDimension)
    .group(monthlyDimensionGroup)
    .x(d3.scaleTime().domain(d3.extent(data, function(d) {
          return new Date(d.date);
        })))
    .transitionDuration(500)
    .elasticY(true)
    .controlsUseVisibility(true)
    .yAxisLabel("Incident count");

  mapChart
    .dimension(mapDimension)
	  .group(mapDimensionGroup)
	  .valueAccessor(d => d.value.count)
	  .center([-40.77,173.59])
	  .zoom(5)
	  .renderPopup(false)
	  .brushOn(true)
	  .cluster(true)
	  .filterByArea(true)
	  .controlsUseVisibility(true)
    .icon(function(d) {
              var iconUrl;
              switch(d.value.IncidentEnvironmentName) {
              case 'Air':
                  iconUrl = 'https://cdn.rawgit.com/pointhi/leaflet-color-markers/master/img/marker-icon-violet.png';
                  break;
              case 'Marine':
                  iconUrl = 'https://cdn.rawgit.com/pointhi/leaflet-color-markers/master/img/marker-icon-blue.png';
                  break;
              case 'Land':
                  iconUrl = 'https://cdn.rawgit.com/pointhi/leaflet-color-markers/master/img/marker-icon-green.png';
                  break;
              case 'Undetermined':
                  iconUrl = 'https://cdn.rawgit.com/pointhi/leaflet-color-markers/master/img/marker-icon-grey.png';
                  break;
              default:
                  iconUrl = 'https://cdn.rawgit.com/pointhi/leaflet-color-markers/master/img/marker-icon-red.png';
              }
              return new L.Icon({
                  iconUrl: iconUrl,
                  shadowUrl: 'https://cdnjs.cloudflare.com/ajax/libs/leaflet/0.7.7/images/marker-shadow.png'
              });
          });

  dc.override(mapChart, 'redraw', function() {
          window.setTimeout(() => mapChart._redraw(), 500);
      });

  // used to reset the map
  // $("#mapReset").on('click', function() {
	// 	mapChart.map().setView([-40.77,173.59], 3);
	//  });

   // date picker function for the sidebar
   $(function() {
     $(".date-picker").datepicker({
       dateFormat: "yy-mm-dd"
     });
   });

   // set behaviour for the date pickers
   // these will set the ranges on the monthly series
   $("#datepicker-from").on('change', function() {
     let date_from = $("#datepicker-from").datepicker("getDate");
     let date_to = $("#datepicker-to").datepicker("getDate");

     // this tests if both date_from and date_to have a selection made
     // if they do then the brush on the monthly series is updated to
     // reflect the selected dates
     if(date_from && date_to){
       monthlyDimension.filterRange([date_from, date_to]);
       monthlySeries.filter(dc.filters.RangedFilter(date_from, date_to));
       dc.redrawAll();
     }
    });

   $("#datepicker-to").on('change', function() {
     let date_from = $("#datepicker-from").datepicker("getDate");
     let date_to = $("#datepicker-to").datepicker("getDate");

     if(date_from && date_to){
       monthlyDimension.filterRange([date_from, date_to]);
       monthlySeries.filter(dc.filters.RangedFilter(date_from, date_to));
       dc.redrawAll();
     }
    });

    // if the monthly series chart is filtered we want to show the
    // current date filter values in the date picker widgets
    monthlySeries.on("filtered", function(chart){
      let filters = chart.filters();
      if(filters.length){
        let range = filters[0];
        $('#datepicker-from').datepicker("setDate", range[0] );
        $('#datepicker-to').datepicker("setDate", range[1] );
      }
    })

  dc.renderAll();

  dc.redrawAll();


});
