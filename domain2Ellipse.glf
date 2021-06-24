#############################################################################
#
# (C) 2021 Cadence Design Systems, Inc. All rights reserved worldwide.
#
# This sample script is not supported by Cadence Design Systems, Inc.
# It is provided freely for demonstration purposes only.
# SEE THE WARRANTY DISCLAIMER AT THE BOTTOM OF THIS FILE.
#
#############################################################################

# Based on http://www.jasondavies.com/random-polygon-ellipse/
# Creates a polygon from the points around the perimeter of a domain
# and iteratively replaces the perimeter with a new one formed from 
# the mid-points of the old perimeter. The result is a planar ellipse 
# even if the starting points are randomly placed in 3D.
# April 2015

# Not sure whether this is the true minimum requirement.
package require PWI_Glyph 2.0.0

########################################################################
# Main Program

# Any value smaller than this is considered to be zero.
set zeroTol 0.000001
# How many times to iterate on the perimeter's shape.
set numIterations 10000
# How many perimeters to keep in the history.
set numHistory 88
set History [list]
# Note: Colors are designed for a black background so that
# the last/oldest curve is invisible.
# Default DB color is af6df0 = 170, 109, 240
set colorFirst [list 255 255 255]
set colorLast  [list   0   0   0]
# Compute the RGB range between the two colors.
set colorRange [list]
for {set i 0} {$i < 3} {incr i} {
   lappend colorRange [expr [lindex $colorLast  $i] - [lindex $colorFirst $i]]
}
# Create a list containing a color for each entity in the history.
# Each color is an RGB triplet blended from the first and last colors.
# RGB is scaled between [0-1] not [0-255].
set colorHistory [list]
for {set c 0} {$c < $numHistory} {incr c} {
   set f [expr $c / ($numHistory - 1.0)]
   set rgb [list]
   for {set i 0} {$i < 3} {incr i} {
      set c1 [lindex $colorFirst $i]
      set cr [lindex $colorRange $i]
      lappend rgb [expr ($c1 + $f * $cr) / 255.0]
   }
   lappend colorHistory $rgb
}


# See if a single domain was already selected
pw::Display getSelectedEntities ents
if { [llength $ents(Domains)] != 1 } {
   puts "One and only one Domain may be selected."
   set selMask [pw::Display createSelectionMask -requireDomain ""]
   set selStatus [pw::Display selectEntities -description "Select a domain." \
      -selectionmask $selMask -single ents]

   if { ! $selStatus } {
      # Nothing was selected - exit.
      exit
   }
}

# Get the selected domain from the selection results.
set domSelected [lindex $ents(Domains) 0]

# Initialize a bounding box.
set bbox [pwu::Extents empty]

# Create a single DB line of the domain's perimeter grid points.
# While doing this, compute the domain's bounding box for use in scaling.
set seg [pw::SegmentSpline create]
# For each connector on each edge of the domain
# copy its grid points into the DB perimeter line
set numEdges [$domSelected getEdgeCount]
for {set e 1} {$e <= $numEdges } {incr e} {
   set edge [$domSelected getEdge $e]
   set numCons [$edge getConnectorCount]
   for {set c 1} {$c <= $numCons} {incr c} {
      set con [$edge getConnector $c]
      set numPoints [$con getDimension]
      set istart 1
      if { $c > 1 } {
         # Don't duplicate the point shared by two cons on the same edge 
         set istart 2
      } elseif { $e > 1 && $c == 1 } {
         # Don't duplicate the point at the node shared by edges. 
         set istart 2
      }
      for {set i $istart} {$i <= $numPoints} {incr i} {
         set P [$con getXYZ -grid $i]
         $seg addPoint $P
         # update bounding box
         set bbox [pwu::Extents enclose $bbox $P]
      }
   }
}

set Perimeter [pw::Curve create]
$Perimeter addSegment $seg
lappend History $Perimeter

# Save the original perimeter's bounding box for scaling calculations.
set bbSizeOrig [pwu::Vector3 subtract [pwu::Extents maximum $bbox] [pwu::Extents minimum $bbox]]

# Iterate on the following:
# Go around the perimeter and create a new perimeter
# from the mid points of the line segments on the old perimeter.
for { set i 1 } { $i <= $numIterations } { incr i } {

   set bbox [pwu::Extents empty]

   set segNew [pw::SegmentSpline create]
   set segOld [$Perimeter getSegment 1]
   set numPoints [$segOld getPointCount]
   # Create a point on the new segment at 
   # the midpoint of two points on the old segment.
   for {set n 2} {$n <= $numPoints} {incr n} {
      set A [$segOld getPoint $n]
      set B [$segOld getPoint [expr $n -1]]
      set Cx [expr ([lindex $A 0] + [lindex $B 0])/2] 
      set Cy [expr ([lindex $A 1] + [lindex $B 1])/2] 
      set Cz [expr ([lindex $A 2] + [lindex $B 2])/2] 
      set P [list $Cx $Cy $Cz]
      if { $n == 2 } {
         # save this first point to re-use as the last point
         set P1 $P
      }
      $segNew addPoint $P
      # Update the bounding box.
      set bbox [pwu::Extents enclose $bbox $P]
   }
   # add the first point as the last point to close the perimeter
   $segNew addPoint $P1
   set newPerimeter [pw::Curve create]
   $newPerimeter addSegment $segNew

   # Compare the total length of the new and old perimeters 
   # to see if we can quit if they're not changing too much.
   set newLength [$newPerimeter getTotalLength]
   set oldLength [   $Perimeter getTotalLength]
   set chgLength [expr abs($newLength - $oldLength) / $oldLength]

   # Add the new perimeter to the end of the history.
   lappend History $newPerimeter
   if { [llength $History] > $numHistory } {
      # If the history is too long, delete the oldest and remove it.
      pw::Entity delete [lindex $History 0]
      set History [lreplace $History 0 0]
   }
   # Delete the old perimeter and replace it with the new one.
   # pw::Entity delete $Perimeter
   set Perimeter $newPerimeter

   # set scale factors based on relative sizes of 
   # original and new perimeters 
   set bbSizeNew [pwu::Vector3 subtract [pwu::Extents maximum $bbox] [pwu::Extents minimum $bbox]]

   set scaleFactorX [expr [pwu::Vector3 X $bbSizeOrig] / [pwu::Vector3 X $bbSizeNew]]
   set scaleFactorY [expr [pwu::Vector3 Y $bbSizeOrig] / [pwu::Vector3 Y $bbSizeNew]]
   if { [expr abs([pwu::Vector3 Z $bbSizeNew])] < $zeroTol } {
     set scaleFactorZ 1.0
   } else {
     set scaleFactorZ [expr [pwu::Vector3 Z $bbSizeOrig] / [pwu::Vector3 Z $bbSizeNew]]
   }
   set scaleFactor [list $scaleFactorX $scaleFactorY $scaleFactorZ] 
   # scale around the center of the new perimeter's bounding box
   set scaleAnchor [pwu::Vector3 add [pwu::Extents minimum $bbox] [pwu::Vector3 divide $bbSizeNew 2.0]]
   # The new perimeter has to be scaled up for visual reasons
   # otherwise it shrinks to nothing.
   pw::Entity transform [pwu::Transform scaling -anchor $scaleAnchor $scaleFactor] $Perimeter

   # Give each perimeter in the history a unique color.
   set np 0
   foreach p $History {
      $p setRenderAttribute ColorMode Entity
      $p setColor [lindex $colorHistory $np]
      incr np 
   }
   # Update the display.
   pw::Display update
}

# if all iterations complete, delete all but the last curve
set History [lreplace $History end end]
pw::Entity delete $History

#############################################################################
#
# This file is licensed under the Cadence Public License Version 1.0 (the
# "License"), a copy of which is found in the included file named "LICENSE",
# and is distributed "AS IS." TO THE MAXIMUM EXTENT PERMITTED BY APPLICABLE
# LAW, CADENCE DISCLAIMS ALL WARRANTIES AND IN NO EVENT SHALL BE LIABLE TO
# ANY PARTY FOR ANY DAMAGES ARISING OUT OF OR RELATING TO USE OF THIS FILE.
# Please see the License for the full text of applicable terms.
#
#############################################################################

