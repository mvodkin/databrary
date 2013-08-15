package controllers

import play.api._
import          Play.current
import          mvc._
import          data._
import          i18n.Messages
import          db.DB
import dbrary._
import util._
import models._

abstract class SiteRequest[A](request : Request[A], val identity : Party, val db : util.Site.DB)
  extends WrappedRequest[A](request) with Site {
  def clientIP = Inet(request.remoteAddress)
}

class AnonRequest[A](request : Request[A], db : util.Site.DB)
  extends SiteRequest[A](request, models.Party.Nobody, db) {
  override def user = None
}

class UserRequest[A](request : Request[A], val account : Account, db : util.Site.DB)
  extends SiteRequest[A](request, account, db) {
  override def user = Some(account)
}

object SiteAction {
  private[this] def getUser(request : Request[_])(implicit db : util.Site.DB) : Option[Account] =
    request.session.get("user").flatMap { i => 
      try { Some(models.Account.asId(i.toInt)) }
      catch { case e:java.lang.NumberFormatException => None }
    }.flatMap(models.Account.get _)

  def apply(anon : AnonRequest[AnyContent] => Result, user : UserRequest[AnyContent] => Result) : Action[AnyContent] =
    Action { request => DB.withTransaction { implicit db =>
      getUser(request).fold(anon(new AnonRequest(request, db)))(u => user(new UserRequest(request, u, db)))
    } }

  def apply(block : SiteRequest[AnyContent] => Result) : Action[AnyContent] =
    apply(block(_), block(_))
}

object UserAction {
  def apply(block : UserRequest[AnyContent] => Result) : Action[AnyContent] = 
    SiteAction(_ => Login.needLogin, block(_))
}

class SiteController extends Controller {
  implicit def db(implicit site : Site) : util.Site.DB = site.db
}

object Site extends SiteController {
  def isSecure : Boolean =
    current.configuration.getString("application.secret").exists(_ != "databrary").
      ensuring(_ || !Play.isProd, "Running insecure in production")
  
  def start = SiteAction(request => Ok(Login.viewLogin()), implicit request =>
    Ok(views.html.party(request.identity, Permission.ADMIN)))

  def test = Action { request => DB.withConnection { implicit db =>
    Ok("Ok")
  } }

  def untrail(path : String) = Action {
    MovedPermanently("/" + path)
  }
}
