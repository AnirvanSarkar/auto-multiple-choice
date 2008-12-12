<?xml version='1.0'?> <!-- -*- coding:utf-8 -*-  -->
<xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform" version="1.0">
<xsl:import href="/usr/share/xml/docbook/stylesheet/nwalsh/xhtml/chunk.xsl"/>
<xsl:param name="use.id.as.filename" select="1"/>
<xsl:param name="admon.graphics" select="1"/>
<xsl:param name="footer.rule" select="0"/>
<xsl:param name="admon.graphics.path" select="'../images/'"/>
<xsl:param name="html.stylesheet" select="'../pages.css ../style.css'"/>
<xsl:param name="callout.graphics.path" select="'../images/callouts/'"/>
<xsl:param name="chunker.output.doctype-public" select="'-//W3C//DTD XHTML 1.0 Transitional//EN'"/>
<xsl:param name="chunker.output.doctype-system" select="'http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd'"/>

<xsl:template name="header.navigation">
  <xsl:param name="prev" select="/foo"/>
  <xsl:param name="next" select="/foo"/>
  <xsl:param name="nav.context"/>

      <div id="top">
          <h1>
            <a href="../index.shtml" title="Page d'accueil de AMC">AMC</a>
          </h1>
          <p>Correction automatisée de formulaires QCM</p>      
      </div>

      
      <div id="navbar" class="doc">
      <table class="zero" width="100%">
      <tr>
      <td class="gauche" width="25%">
        <xsl:if test="count($prev)&gt;0">
	<a accesskey="p">
                    <xsl:attribute name="href">
                      <xsl:call-template name="href.target">
                        <xsl:with-param name="object" select="$prev"/>
                      </xsl:call-template>
                    </xsl:attribute>
                    <xsl:call-template name="navig.content">
                      <xsl:with-param name="direction" select="'prev'"/>
                    </xsl:call-template>
                  </a>
	</xsl:if>
	</td>
	<td class="milieu">
	<a href="../index.shtml">Accueil</a> » <a href="index.html">Doc</a> » <xsl:apply-templates select="." mode="object.title.markup"/>
	</td>
	<td class="droite" width="25%">
        <xsl:if test="count($next)&gt;0">
	<a accesskey="n">
                    <xsl:attribute name="href">
                      <xsl:call-template name="href.target">
                        <xsl:with-param name="object" select="$next"/>
                      </xsl:call-template>
                    </xsl:attribute>
                    <xsl:call-template name="navig.content">
                      <xsl:with-param name="direction" select="'next'"/>
                    </xsl:call-template>
                  </a>
	</xsl:if>
	</td>
	</tr></table>
      </div>
</xsl:template>

</xsl:stylesheet>
