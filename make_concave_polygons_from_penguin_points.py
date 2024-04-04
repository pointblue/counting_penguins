import numpy as np
from sklearn.cluster import DBSCAN
from shapely.geometry import MultiPoint
import os
import geopandas as gpd
import alphashape

# Path to your point shapefile
input_file_path = "C:\\gballard\\S031\\analyses\\counting_penguins\\predict\\2023\\bird_north_adpe_2023-11-30_lcc169\\counts\\ADPE_20231024_adult_sit\\GIS\\masked_labels.shp"

# Load the shapefile
points_gdf = gpd.read_file(input_file_path)

# Perform clustering on the points
# Note: Adjust 'eps' and 'min_samples' as needed for your specific dataset
coords = np.array(list(zip(points_gdf.geometry.x, points_gdf.geometry.y)))
db = DBSCAN(eps=3, min_samples=3).fit(coords)  # Example parameters
points_gdf['cluster'] = db.labels_

# Filter out noise (-1 labels, if any)
clusters_gdf = points_gdf[points_gdf['cluster'] != -1]

# Function to generate a concave hull (alpha shape) from a list of points
def generate_concave_hull(points_list, alpha=1.0):
    """
    Generate a concave hull for a given list of Shapely points.

    Args:
    points_list: List of Shapely Point objects.
    alpha: Alpha value to control the concave hull granularity.

    Returns:
    A Shapely Polygon representing the concave hull.
    """
    if len(points_list) > 3:
        # Convert Shapely Point objects to a list of (x, y) tuples
        points_coords = [(point.x, point.y) for point in points_list]

        # Generate the alpha shape (concave hull)
        alpha_shape = alphashape.alphashape(points_coords, alpha)
        return alpha_shape
    else:
        # If the cluster has 3 or fewer points, just return their convex hull
        return MultiPoint(points_list).convex_hull

# Replace your convex hull generation with concave hull generation
concave_polygons = []
for cluster_label in clusters_gdf['cluster'].unique():
    cluster_points = clusters_gdf[clusters_gdf['cluster'] == cluster_label]
    points_list = [point for point in cluster_points.geometry]

    if points_list:
        # Generate concave hull
        concave_hull = generate_concave_hull(points_list, alpha=1.0)  # Adjust alpha as needed

        # Optionally, you can still apply a buffer to the concave hull
        buffer_distance = 1  # meters
        buffered_hull = concave_hull.buffer(buffer_distance)  # Assuming buffer_distance is defined

        concave_polygons.append(buffered_hull)

# Create a new GeoDataFrame
concave_hulls_gdf = gpd.GeoDataFrame(geometry=concave_polygons)

# Continue with saving the GeoDataFrame as a shapefile
output_file_path = os.path.join(os.path.dirname(input_file_path), "clustered_concave_polygons.shp")
concave_hulls_gdf.to_file(output_file_path)
