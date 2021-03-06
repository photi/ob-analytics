## Copyright (C) 2015,2016 Philip Stubbings <phil@parasec.net>
## Licensed under the GPL v2 license. See LICENSE.md for full terms.

##' Import CSV file.
##'
##' Imports and performs preprocessing of limit order data contained in a CSV.
##'
##' The CSV file is expected to contain 7 columns:
##'
##' \describe{
##'   \item{id}{Numeric limit order unique identifier}
##'   \item{timestamp}{Time in milliseconds when event received locally}
##'   \item{exchange.timestamp}{Time in milliseconds when order first created on
##' the exchange}
##'   \item{price}{Price level of order event}
##'   \item{volume}{Remaining order volume}
##'   \item{action}{Event type (see below)}
##'   \item{direction}{Side of order book (bid or ask)}
##' }
##'
##' \emph{action} describes the limit order life-cycle:
##'
##' \describe{
##'   \item{created}{The limit order has been created}
##'   \item{modified}{The limit order has been modified (partial fill)}
##'   \item{deleted}{The limit order was deleted. If the remaining volume is 0,
##' the order has been filled.}
##' }
##' 
##' An example dataset returned from this function can be seen in
##' \code{\link{lob.data}} which is the result of processing the example data
##' included in the \code{inst/extdata} directory of this package.
##' 
##' @param csv.file Location of CSV file to import
##' @return A list containing 4 data frames:
##' \describe{
##'   \item{\link{events}}{Limit order events.}
##'   \item{\link{trades}}{Inferred trades (executions).}
##'   \item{\link{depth}}{Order book price level depth through time.}
##'   \item{\link{depth.summary}}{Limit order book summary statistics.}
##' }
##' @author phil
##' @examples
##' \dontrun{
##'
##' csv.file <- system.file("extdata", "orders.csv.xz", package="obAnalytics")
##' lob.data <- processData(csv.file)
##' }
##' @export processData
processData <- function(csv.file) {

  getZombieIds <- function(events, trades) {
    cancelled <- events[events$action == "deleted", ]$id
    zombies <- events[!events$id %in% cancelled, ]
    bid.zombies <- zombies[zombies$direction == "bid", ]
    ask.zombies <- zombies[zombies$direction == "ask", ]
    bid.zombie.ids <- unique(bid.zombies[unlist(lapply(bid.zombies$id, 
        function(id) {
      zombie <- tail(bid.zombies[bid.zombies$id == id, ], 1)
      any(trades$direction == "sell" & trades$timestamp >= zombie$timestamp 
          & trades$price < zombie$price)
    })), "id"])
    ask.zombie.ids <- unique(ask.zombies[unlist(lapply(ask.zombies$id, 
        function(id) {
      zombie <- tail(ask.zombies[ask.zombies$id == id, ], 1)
      any(trades$direction == "buy" & trades$timestamp >= zombie$timestamp 
          & trades$price > zombie$price)
    })), "id"])
    c(bid.zombie.ids, ask.zombie.ids)
  }

  events <- loadEventData(csv.file)
  events <- eventMatch(events)
  trades <- matchTrades(events)
  events <- setOrderTypes(events, trades)
  zombie.ids <- getZombieIds(events, trades)
  events <- events[!events$id %in% zombie.ids, ]

  depth <- priceLevelVolume(events)
  depth.summary <- depthMetrics(depth)
  events <- orderAggressiveness(events, depth.summary)
  # depth summary data starts 1 minute later to allow for order book population.
  offset <- min(events$timestamp) + 60
  list(
    events=events, 
    trades=trades, 
    depth=depth, 
    depth.summary=depth.summary[depth.summary$timestamp >= offset, ]
  )
}

##' Load pre-processed data. 
##'
##' Loads previously saved pre-processed data.
##'
##' Convenience function.
##'
##' @param bin.file File location.
##' @param ... \code{\link{readRDS}}.
##' @return Limit order, trade and depth data structure \code{\link{lob.data}}.
##' @author phil
##' @examples
##' \dontrun{
##' 
##' lob.data <- loadData(bin.file="/tmp/lob.data.rds")
##' }
##' @export loadData
loadData <- function(bin.file, ...) {
  readRDS(file=bin.file, ...)
}

##' Save processed data.
##'
##' Saves processed data to file. 
##'
##' Convenience function.
##'
##' @param lob.data \code{\link{lob.data}} data structure.
##' @param bin.file File to save to.
##' @param ... \code{\link{saveRDS}}.
##' @author phil
##' @examples
##' \dontrun{
##' 
##' saveData(lob.data, bin.file="/tmp/lob.data.rds", compress="xz")
##' }
##' @export saveData
saveData <- function(lob.data, bin.file, ...) {
  saveRDS(lob.data, file=bin.file, ...)
}
