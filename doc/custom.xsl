<xsl:stylesheet version="1.0"
  xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:d="http://docbook.org/ns/docbook">
  
  <!-- Your customizations go here -->
  <xsl:param name="figure.important">important</xsl:param>
  <xsl:param name="figure.note">note</xsl:param>
  <xsl:param name="local.l10n.xml" select="document('customl10n.xml')"/>
  
  <xsl:template match="itemizedlist" mode="print">
    <xsl:apply-templates select="title"/>
    <xsl:apply-templates select="*[not(self::title or
                                 self::titleabbrev or
                                 self::listitem)]"/>
    <xsl:text>\begin{itemize}</xsl:text>
    <!-- Process the option -->
    <xsl:call-template name="opt.group">
      <xsl:with-param name="opts" select="@spacing"/>
      <xsl:with-param name="mode" select="'enumitem'"/>
    </xsl:call-template>
    <xsl:choose>
      <xsl:when test="contains(@role, 'raggedright')">
        <xsl:text>\raggedright{}</xsl:text>
      </xsl:when>
    </xsl:choose>
    <xsl:text>&#10;</xsl:text>
    <xsl:apply-templates select="listitem"/>
    <xsl:text>\end{itemize}&#10;</xsl:text>
  </xsl:template>

</xsl:stylesheet>
