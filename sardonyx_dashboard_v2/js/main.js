
const dateFormatSpecifier = '%Y-%m-%d';
const dateFormat = d3.timeFormat(dateFormatSpecifier);
const dateFormatParser = d3.timeParse(dateFormatSpecifier);

let categoryChart = dc.pieChart('#category-piechart');
let environmentChart = dc.rowChart('#environment-rowchart');
let LivesSavedND = dc.numberDisplay("#LivesSaved"),
    LivesRescuedND = dc.numberDisplay("#LivesRescued"),
    LivesAssistedND = dc.numberDisplay("#LivesAssisted"),
    LivesLostND = dc.numberDisplay("#LivesLost");
let responseChart = dc.rowChart('#response-rowchart');
let monthlySeries = dc.lineChart('#incident-series');
let mapChart = dc_leaflet.markerChart("#map-chart");

monthlySeries.margins().left = 40;


d3.csv('data/sardonyx_data.csv').then(function (data) {
  data.forEach(function (d) {
        d.ConfirmedLatitude = +d.LocationFindLocationLatitude;
        d.ConfirmedLongitude = +d.LocationFindLocationLongitude;
        d.date = dateFormatParser(d.date);
        d.date2 = dateFormat(d.date);
        d.month = d3.timeMonth(d.date);
        d.geo = d.LocationFindLocationLatitude + "," + d.LocationFindLocationLongitude;
        d.LivesSaved = +d.LivesSaved;
        d.LivesRescued = +d.LivesRescued;
        d.LivesAssisted = +d.LivesAssisted;
        d.LivesLost = +d.NumberPerishedOrAssumedPerished;
    });

  console.log(data);

  /* now we create the crossfilter and set up the dimensions and groups*/
  let ndx = crossfilter(data);
  let all = ndx.groupAll();


  /* create a dimension for monthly incidents */
  let monthlyDimension = ndx.dimension(function (d) {
        return d.month;
    });

  let monthlyDimensionGroup = monthlyDimension.group();

  let metricsGroup = ndx.groupAll().reduce(
    function(p, v){
      ++p.count;
      p.TotalLivesSaved += v.LivesSaved;
      p.TotalLivesRescued += v.LivesRescued;
      p.TotalLivesAssisted += v.LivesAssisted;
      p.TotalLivesLost += v.LivesLost;
      return p;
    },
    function(p, v){
      --p.count;
      p.TotalLivesSaved -= v.LivesSaved;
      p.TotalLivesRescued -= v.LivesRescued;
      p.TotalLivesAssisted -= v.LivesAssisted;
      p.TotalLivesLost -= v.LivesLost;
      return p;
    },
    function(){
      return{
        count: 0,
        TotalLivesSaved: 0,
        TotalLivesRescued: 0,
        TotalLivesAssisted: 0,
        TotalLivesLost: 0
      };

    }
  );

console.log(metricsGroup);

  /* create a dimension for SAR Category */
  let categoryDimension = ndx.dimension(function (d) {
        return d.SarCategory;
    });

  let categoryDimensionGroup = categoryDimension.group();



  /* create a dimension for Response type */
  let responseDimension = ndx.dimension(function (d) {
        return d.Response;
    });

  let responseDimensionGroup = responseDimension.group();


  /* create a dimension for Environment */
  let environmentDimension = ndx.dimension(function (d) {
        return d.Environment;
    });

  let environmentDimensionGroup = environmentDimension.group();


  /* create a dimension for map data */
  let mapDimension = ndx.dimension(function (d) {
        return d.geo;
    });

  let mapDimensionGroup = mapDimension.group().reduce(
          function(p, v) {
              p.Environment = v.Environment;
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
      return p.TotalLivesSaved;
    })
    .group(metricsGroup);

  LivesRescuedND
    .formatNumber(d3.format(",.2r"))
    .valueAccessor(function(p){
      return p.TotalLivesRescued;
    })
    .group(metricsGroup);

  LivesAssistedND
    .formatNumber(d3.format(",.2r"))
    .valueAccessor(function(p){
      return p.TotalLivesAssisted;
    })
    .group(metricsGroup);

  LivesLostND
    .formatNumber(d3.format(",.2r"))
    .valueAccessor(function(p){
      return p.TotalLivesLost;
    })
    .group(metricsGroup);


  /* build pie chart for Categories*/
  categoryChart
    .radius(null)
    .dimension(categoryDimension)
    .group(categoryDimensionGroup)
    .transitionDuration(500)
    .controlsUseVisibility(true)
    .width(100)
    .height(100);

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


  /* build row chart for Responses*/
  responseChart
    .width(150)
    .height(150)
    .margins({top: 0, left: 10, right: 10, bottom: 20})
    .dimension(responseDimension)
    .group(responseDimensionGroup)
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
              switch(d.value.Environment) {
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
