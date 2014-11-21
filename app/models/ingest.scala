package models

import scala.concurrent.{ExecutionContext,Future}
import dbrary._

object Ingest {
  def getContainer(v : Volume, key : String)(implicit dbc : site.Site.DB, exc : ExecutionContext) : Future[Option[Container]] =
    models.Container.rowVolume(v)
    .SELECT("JOIN ingest.container AS ingest ON container.id = ingest.id AND container.volume = ingest.volume WHERE key = ?")
    .apply(key).singleOpt

  def setContainer(container : Container, key : String)(implicit dbc : site.Site.DB, exc : ExecutionContext) : Future[Unit] =
    SQL("INSERT INTO ingest.container (id, volume, key) VALUES (?, ?, ?)")
    .apply(container.id, container.volumeId, key).ensure

  def getRecord(v : Volume, key : String)(implicit dbc : site.Site.DB, exc : ExecutionContext) : Future[Option[Record]] =
    models.Record.rowVolume(v)
    .SELECT("JOIN ingest.record AS ingest ON record.id = ingest.id AND record.volume = ingest.volume WHERE key = ?")
    .apply(key).singleOpt

  def setRecord(record : Record, key : String)(implicit dbc : site.Site.DB, exc : ExecutionContext) : Future[Unit] =
    SQL("INSERT INTO ingest.record (id, volume, key) VALUES (?, ?, ?)")
    .apply(record.id, record.volumeId, key).ensure

  def getAsset(v : Volume, path : String)(implicit dbc : site.Site.DB, exc : ExecutionContext) : Future[Option[Asset]] =
    models.Asset.rowVolume(v)
    .SELECT("JOIN ingest.asset AS ingest ON asset.id = ingest.id WHERE file = ?")
    .apply(path).singleOpt

  def getAssetClip(o : Asset, clip : Segment)(implicit dbc : site.Site.DB, exc : ExecutionContext) : Future[Option[Asset]] =
    models.Asset.rowVolume(o.volume)
    .SELECT("JOIN transcode ON asset.id = transcode.asset WHERE transcode.orig = ? AND segment = ?")
    .apply(o.id, clip).singleOpt

  def setAsset(asset : Asset, path : String)(implicit dbc : site.Site.DB, exc : ExecutionContext) : Future[Unit] =
    SQL("INSERT INTO ingest.asset (id, file) VALUES (?, ?)")
    .apply(asset.id, path).ensure
}
