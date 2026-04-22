############################################
## Solutions for HW 3 - Introduction to R ##
############################################

### Homework 3A
# assign your sorted data to "irismod"
irismod <- iris[order(iris[,1]), order(colnames(iris))]
irissub <- irismod[1:12,]
write.table(irissub, file="irissub.xls", sep="\t", quote=FALSE, row.names=FALSE)
irisimport <- read.delim(file="irissub.xls", sep="\t")

### Homework 3B
plot(iris[,1], iris[,2], col=iris$Species, lwd=2, pch=19)
plot(iris[,1], iris[,2], col=iris$Species, lwd=2, pch=19, xlim=c(4,16), ylim=c(2,8))

### Homework 3C
mMA <- sapply(colnames(iris[,1:4]), function(x) tapply(iris[,x], iris[,5], mean))
barplot(mMA, beside=FALSE, legend=rownames(mMA))
barplot(mMA, beside=TRUE, legend=rownames(mMA))

# load data
my_mw <- read.delim(file="https://faculty.ucr.edu/~tgirke/Documents/R_BioCond/Samples/MolecularWeight_tair7.xls", header=TRUE, sep="\t")
my_target <- read.delim(file="https://faculty.ucr.edu/~tgirke/Documents/R_BioCond/Samples/TargetP_analysis_tair7.xls", header=TRUE, sep="\t")
colnames(my_target)[1] <- "ID"
colnames(my_mw)[1] <- "ID"
my_mw_target <- merge(my_mw, my_target, by.x="ID", by.y="ID", all.x=TRUE)
my_mw_target2a <- merge(my_mw, my_target[1:40,], by.x="ID", by.y="ID", all.x=TRUE)
my_mw_target2 <- na.omit(my_mw_target2a)
### Homework 3D
my_mw_target_tmp <- merge(my_mw, my_target[1:40,], by.x="ID", by.y="ID", all=FALSE)
all(my_mw_target2 == my_mw_target_tmp)

### Homework 3E
my_mw_target2a[is.na(my_mw_target2a)] <- 0

### Homework 3F
query2 <- my_mw_target[my_mw_target[, 2] > 4000 & my_mw_target[, 2] < 5000, ]
dim(query2)
query2[order(query2[,2]),]

### Homework 3G
my_mw_target3 <- data.frame(loci=gsub("\\..*", "", as.character(my_mw_target[,1]), perl = TRUE), my_mw_target)
## First option via %in%
myids <- c("AT5G52930.1", "AT4G18950.1", "AT1G15385.1", "AT4G36500.1", "AT1G67530.1")
index <- my_mw_target3[,2] %in% myids
query3A <- my_mw_target3[index, ]

## Alternative via rowname index is more convenient and reusable
rownames(my_mw_target3) <- my_mw_target3[,2]
query3B <- my_mw_target3[myids,]

### Homework 3H
source("exerciseRbasics.R")

