
const dateFormatSpecifier = '%Y-%m-%d';
const dateFormat = d3.timeFormat(dateFormatSpecifier);
const dateFormatParser = d3.timeParse(dateFormatSpecifier);

let categoryChart = dc.pieChart('#sarcat-piechart');
let environmentChart = dc.rowChart('#environment-rowchart');
let monthlySeries = dc.lineChart('#incident-series');
let dataTable = dc.dataTable('#datatable');
let mapChart = dc_leaflet.markerChart("#map-chart");

monthlySeries.margins().left = 40;


d3.csv('data/incidents.csv').then(function (data) {
  data.forEach(function (d) {
        d.ConfirmedLatitude = +d.ConfirmedLatitude;
        d.ConfirmedLongitude = +d.ConfirmedLongitude;
        d.date = dateFormatParser(d.date);
        d.date2 = dateFormat(d.date);
        d.month = d3.timeMonth(d.date); 
        d.year = +d.year;
        d.geo = d.ConfirmedLatitude + "," + d.ConfirmedLongitude;
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
    
  /* create a dimension for SAR Category */
  let categoryDimension = ndx.dimension(function (d) {
        return d.Category;
    });
    
  let categoryDimensionGroup = categoryDimension.group();
  
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
  

  
  
  /* build pie chart for Categories*/
  categoryChart
    .radius(80)
    .dimension(categoryDimension)
    .group(categoryDimensionGroup)
    .transitionDuration(500)
    .controlsUseVisibility(true);
    
    
  /* build row chart for Environments*/
  environmentChart
    .dimension(environmentDimension)
    .group(environmentDimensionGroup)
    .transitionDuration(500)
    .controlsUseVisibility(true);
    
  
  /* build line chart for time series*/
  monthlySeries
    .dimension(monthlyDimension)
    .group(monthlyDimensionGroup)
    .x(d3.scaleTime().domain(d3.extent(data, function(d) { 
          return new Date(d.date); 
        })))
    .transitionDuration(500)
    .elasticY(true)
    .controlsUseVisibility(true)
    .yAxisLabel("Incident count");
    
    
  /* build datatable */
  dataTable
    .dimension(monthlyDimension)
    .columns(['SourceAgency', {
                label: 'Date',
                format: function (d) {
                    return d.date2;
                }
            }, 
            'Category', 'Environment'])
    .size(5)
    .sortBy(function (d) {
            return d.date2;
        })
    .order(d3.ascending);
  
  
  mapChart
    .dimension(mapDimension)
	  .group(mapDimensionGroup)
	  .valueAccessor(d => d.value.count)
	  .center([-40.77,173.59])
	  .zoom(3)
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
  
  // used to reset the map
  $("#mapReset").on('click', function() {
		mapChart.map().setView([-40.77,173.59], 3);
	 });
  
  
  
  dc.renderAll();
  
  dc.redrawAll();
  
  
});