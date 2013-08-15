package models

import java.sql.Timestamp
import anorm._
import anorm.SqlParser.scalar
import dbrary._
import dbrary.Anorm._
import util._

object Permission extends PGEnum("permission") {
  val NONE, VIEW, DOWNLOAD, CONTRIBUTE, ADMIN = Value
  // aliases or equivalent permissions (do not use val here)
  def OWN = ADMIN
  def EDIT = CONTRIBUTE
  def DATA = DOWNLOAD
  def COMMENT = VIEW
}

final case class Authorize(childId : Party.Id, parentId : Party.Id, access : Permission.Value, delegate : Permission.Value, authorized : Option[Timestamp], expires : Option[Timestamp]) extends TableRow {
  private def id =
    Anorm.Args('child -> childId, 'parent -> parentId)
  private def args =
    id ++ Anorm.Args('access -> access, 'delegate -> delegate, 'authorized -> authorized, 'expires -> expires)

  /* update or add; this and remove may both invalidate child.access */
  def set(implicit site : Site) : Unit = {
    val args = this.args
    if (Audit.SQLon(AuditAction.change, Authorize.table, "SET access = {access}, delegate = {delegate}, authorized = {authorized}, expires = {expires} WHERE child = {child} AND parent = {parent}")(args : _*).executeUpdate()(site.db) == 0)
      Audit.SQLon(AuditAction.add, Authorize.table, Anorm.insertArgs(args))(args : _*).execute()(site.db)
  }
  def remove(implicit site : Site) : Unit =
    Authorize.delete(childId, parentId)

  def valid = {
    val now = (new java.util.Date).getTime
    authorized.fold(false)(_.getTime < now) && expires.fold(true)(_.getTime > now)
  }

  private[Authorize] val _child = CachedVal[Party, Site](Party.get(childId)(_).get)
  def child(implicit site : Site) : Party = _child
  private[Authorize] val _parent = CachedVal[Party, Site](Party.get(parentId)(_).get)
  def parent(implicit site : Site) : Party = _parent
}

object Authorize extends Table[Authorize]("authorize") {
  private[models] val row = Columns[
    Party.Id, Party.Id, Permission.Value, Permission.Value, Option[Timestamp], Option[Timestamp]](
    'child,    'parent,   'access,          'delegate,        'authorized,       'expires).
    map(Authorize.apply _)

  private[this] def SELECT(all : Boolean, q : String) : SimpleSql[Authorize] = 
    SELECT("WHERE " + (if (all) "" else "authorized < CURRENT_TIMESTAMP AND (expires IS NULL OR expires > CURRENT_TIMESTAMP) AND ") + q)

  def get(c : Party.Id, p : Party.Id)(implicit db : Site.DB) : Option[Authorize] =
    SELECT(true, "child = {child} AND parent = {parent}").
      on('child -> c, 'parent -> p).singleOpt()

  private[models] def getParents(c : Party, all : Boolean)(implicit db : Site.DB) =
    SELECT(all, "child = {child}").
      on('child -> c.id).list(
        row map { a => a._child() = c ; a }
      )
  private[models] def getChildren(p : Party, all : Boolean)(implicit db : Site.DB) =
    SELECT(all, "parent = {parent}").
      on('parent -> p.id).list(
        row map { a => a._parent() = p ; a }
      )

  def delete(c : Party.Id, p : Party.Id)(implicit site : Site) =
    Audit.SQLon(AuditAction.remove, "authorize", "WHERE child = {child} AND parent = {parent}")('child -> c, 'parent -> p).
      execute()(site.db)

  private[models] def access_check(c : Party.Id)(implicit db : Site.DB) : Permission.Value =
    SQL("SELECT authorize_access_check({id})").
      on('id -> c).single(scalar[Option[Permission.Value]]).
      getOrElse(Permission.NONE)

  private[models] def delegate_check(c : Party.Id, p : Party.Id)(implicit db : Site.DB) : Permission.Value =
    SQL("SELECT authorize_delegate_check({child}, {parent})").
      on('child -> c, 'parent -> p).single(scalar[Option[Permission.Value]]).
      getOrElse(Permission.NONE)
}
